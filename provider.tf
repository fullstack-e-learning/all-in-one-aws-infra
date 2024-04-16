terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.41"
    }

    ansible = {
      version = "~> 1.2.0"
      source  = "ansible/ansible"
    }

    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "1.22.0"
    }
  }
  backend "s3" {
    bucket = "tfpocbucket001"
    key    = "ec2-efs/all-in-one/terraform.tfstate"
    region = "eu-north-1"
  }
}

provider "aws" {
  region = "eu-north-1"
}

provider "postgresql" {
  host     = "localhost"
  port     = 5432
  username = "postgres"
  password = random_password.postgres_password.result
}
