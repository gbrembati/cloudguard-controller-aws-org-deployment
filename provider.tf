terraform {
  required_version = "~> 1.4.0"
  required_providers {
    random = {
      source = "hashicorp/random"
      version = "~> 3.5.0"
    }
    aws = {
      source = "hashicorp/aws"
      version = "~> 4.44.0"
    }
    checkpoint = {
      source  = "checkpointsw/checkpoint"
      version = "~> 2.3.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region     = var.aws-region
  access_key = var.aws-access-key
  secret_key = var.aws-secret-key
}

# Configure the Check Point Provider
provider "checkpoint" {
  server        = var.chkp-management.server
  api_key       = var.chkp-management-api-key
}
