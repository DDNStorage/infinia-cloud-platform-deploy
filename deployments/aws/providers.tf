provider "aws" {
  region = var.aws_region
}

terraform {
  backend "s3" {
    # bucket         = ""  # Use the same bucket name as specified in terraform.tfvars
    # key            = "infinia/state.tfstate"
    # region         = "us-east-1"
  }
}
