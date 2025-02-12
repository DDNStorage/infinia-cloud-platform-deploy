provider "aws" {
  region = var.aws_region
}

terraform {
  backend "s3" {
    bucket         = "infinia-tf-state"
    key            = "terraform/state.tfstate"
    region         = "us-east-1"
  }
}
