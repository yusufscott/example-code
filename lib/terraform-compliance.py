#!/usr/local/env python

import boto3
import os


def install():
    os.system('apt-get install -y gnupg software-properties-common curl')
    os.system('curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add -')
    os.system('apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"')
    os.system('apt-get update && apt-get install terraform=1.0.0 -y')
    os.system('pip install terraform-compliance')

def scan():
    os.system('terraform init')
    os.system('terraform plan -out=plan.out')
    os.system('terraform-compliance -f git:https://github.com/terraform-compliance/user-friendly-features.git -p plan.out --no-ansi > reports/terraform-report.txt')

def main():
    install()
    scan()

if __name__ == "__main__":
    main()
