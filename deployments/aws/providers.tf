provider "aws" {
  region = var.aws_region
}

terraform {
  backend "s3" {
    bucket = "infinia-tf-state-2-0-20"
    key    = "infinia/state.tfstate"
    region = "us-east-1"
  }
}
