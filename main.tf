provider "aws" {
    region = "us-west-2"
    #profile = "vr"
}

resource "aws_secretsmanager_secret" "docker_login" {
    name = "vr/docker-login"
    description = "Used to log into Docker Hub"
}

resource "aws_secretsmanager_secret_version" "docker_login" {
    secret_id = aws_secretsmanager_secret.docker_login.id
    secret_string = jsonencode(var.docker_credentials)
}

resource "aws_secretsmanager_secret" "sc_login" {
    name = "vr/sc-login"
    description = "Used to log into SonarCloud"
}

resource "aws_secretsmanager_secret_version" "sc_login" {
    secret_id = aws_secretsmanager_secret.sc_login.id
    secret_string = jsonencode(var.sc_credentials)
}

resource "aws_s3_bucket" "audit_report_log_bucket" {
  bucket = "yusufs-audit-report-log-bucket"
  acl    = "log-delivery-write"
  force_destroy = true
  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
        apply_server_side_encryption_by_default {
            sse_algorithm = "aws:kms"
        }
    }
  }
}

resource "aws_s3_bucket" "audit_report_bucket" {
    bucket = "yusufs-audit-report-bucket"
    acl = "private"
    force_destroy = true
    versioning {
        enabled = true
    }

    logging {
        target_bucket = aws_s3_bucket.audit_report_log_bucket.id
        target_prefix = "log/"
    }

    server_side_encryption_configuration {
        rule {
            apply_server_side_encryption_by_default {
                sse_algorithm = "aws:kms"
            }
        }
    }
}

resource "aws_codestarconnections_connection" "code_base" {
    name = "example-code"
    provider_type = "GitHub"
}

resource "aws_iam_role" "audit_pipeline_role" {
    name = "audit_pipeline_role"
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = "sts:AssumeRole"
                Effect = "Allow"
                Sid = ""
                Principal = {
                    Service = "codepipeline.amazonaws.com"
                }
            },
        ]
    })
}

resource "aws_iam_role" "audit_build_role" {
    name = "audit_build_role"
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = "sts:AssumeRole"
                Effect = "Allow"
                Sid = ""
                Principal = {
                    Service = "codebuild.amazonaws.com"
                }
            },
        ]
    })
}

resource "aws_iam_role_policy" "audit_pipeline_role_policy" {
    name = "audit_pipeline_role_policy"
    role = aws_iam_role.audit_pipeline_role.id
    policy = jsonencode({
        Version=  "2012-10-17",
        Statement = [
            {
                Effect = "Allow",
                Action = [
                    "s3:GetObject",
                    "s3:GetObjectVersion",
                    "s3:GetBucketVersioning",
                    "s3:PutObjectAcl",
                    "s3:PutObject"
                ],
                Resource = [
                    "${aws_s3_bucket.audit_report_bucket.arn}",
                    "${aws_s3_bucket.audit_report_bucket.arn}/*"
                ]
            },
            {
                Effect = "Allow",
                Action = [
                    "codestar-connections:UseConnection"
                ],
                Resource = "${aws_codestarconnections_connection.code_base.arn}"
            },
            {
                Effect = "Allow",
                Action = [
                    "codebuild:BatchGetBuilds",
                    "codebuild:StartBuild"
                ],
                Resource = "*"
            },
        ]
    })
}

resource "aws_iam_role_policy" "audit_build_role_policy" {
  role = aws_iam_role.audit_build_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
        {
            Effect = "Allow",
            Resource = [
                "*"
            ],
            Action = [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ]
        },
        {
            Effect = "Allow",
            Action = [
                "ec2:CreateNetworkInterface",
                "ec2:DescribeDhcpOptions",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DeleteNetworkInterface",
                "ec2:DescribeSubnets",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeVpcs"
            ],
            Resource = "*"
        },
        {
            Effect = "Allow",
            Action = [
                "ec2:CreateNetworkInterfacePermission"
            ],
            Resource = [
                "arn:aws:ec2:us-east-1:123456789012:network-interface/*"
            ],
            Condition = {
                StringEquals = {
                "ec2:Subnet" = [
                    "subnet-example1",
                    "subnet-example2"
                ],
                "ec2:AuthorizedService" = "codebuild.amazonaws.com"
                }
            }
        },
        {
            Effect = "Allow",
            Action = [
                "s3:*"
            ],
            Resource = [
                "${aws_s3_bucket.audit_report_bucket.arn}",
                "${aws_s3_bucket.audit_report_bucket.arn}/*"
            ]
        },
        {
            Effect = "Allow",
            Action = [
                "secretsmanager:GetSecretValue"
            ],
            Resource = [
                "arn:aws:secretsmanager:*:753641548906:secret:*"
            ]
        }
    ]
  })
}

resource "aws_codebuild_project" "example" {
  name          = "audit-pipeline"
  description   = "Demonstration of audit pipelines"
  build_timeout = "5"
  service_role  = aws_iam_role.audit_build_role.arn

  artifacts {
    type = "S3"
    location = aws_s3_bucket.audit_report_bucket.bucket
    name = "audit-report"
    namespace_type = "BUILD_ID"
    packaging = "ZIP"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:5.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true
  }


  source {
    type            = "GITHUB"
    location        = "https://github.com/yusufscott/example-code.git"
    git_clone_depth = 1

    git_submodules_config {
      fetch_submodules = true
    }
  }

  source_version = "main"
}

resource "aws_codepipeline" "audit_pipeline" {
  name = "tf-test-pipeline"
  role_arn = aws_iam_role.audit_pipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.audit_report_bucket.bucket
    type = "S3"
  }

  stage {
    name = "Source"

    action {
      name = "Source"
      category = "Source"
      owner = "AWS"
      provider = "CodeStarSourceConnection"
      version = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn = aws_codestarconnections_connection.code_base.arn
        FullRepositoryId = "yusufscott/example-code"
        BranchName = "main"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name = "Build"
      category = "Build"
      owner = "AWS"
      provider = "CodeBuild"
      input_artifacts = ["source_output"]
      output_artifacts = ["build_output"]
      version = "1"

      configuration = {
        ProjectName = "audit-pipeline"
      }
    }
  }

  stage {
    name = "Approval"

    action {
        name = "Manual_Approval"
        category = "Approval"
        owner = "AWS"
        provider = "Manual"
        version = "1"
    }
  }
}
