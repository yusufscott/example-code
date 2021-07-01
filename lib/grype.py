#!/usr/local/env python

import boto3
import os


def install():
    os.system('curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin')

def scan():
    os.system('grype $imageid > reports/grype-report.txt')
    
def main():
    install()
    scan()

if __name__ == "__main__":
    main()
