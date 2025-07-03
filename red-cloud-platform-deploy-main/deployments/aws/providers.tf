provider "aws" {
  region = var.aws_region
}

terraform {
  backend "s3" {
    bucket         = "infinia-tf-state-shiloh.t"
    key            = "infinia/state.tfstate"
    region         = "us-east-1"
  }
}
