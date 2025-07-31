provider "aws" {
  region = var.aws_region
}

terraform {
  backend "s3" {
    bucket = "terraform-dev-raid"
    key    = "infinia/state.tfstate"
    region = "us-east-1"
  }
}
