provider "aws" {
  region = var.aws_region
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.14.0"
    }
  }
  backend "s3" {
    bucket = "infinia-terraform-state-471441381769"
    key    = "infinia/state.tfstate"
    region = "us-east-1"
  }
}
