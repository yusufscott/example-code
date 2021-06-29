variable "docker_credentials" {
    type = map(string)
    sensitive = true
    default = {
        username = "username"
        password = "password"
    }
}

variable "sc_credentials" {
    type = map(string)
    sensitive = true
    default = {
        SONAR_TOKEN = "test_token"
        HOST = "https://sonarcloud.io"
        Organization = "test_org"
        Project = "test_project"
    }
}
