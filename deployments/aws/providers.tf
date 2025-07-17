provider "aws" {
  region = var.aws_region
}

terraform {
  backend "s3" {
    bucket = "infinia-tf-state-customer"
    key    = "infinia/state.tfstate"
    region = "us-west-1"
  }
}
