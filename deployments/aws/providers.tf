provider "aws" {
  region = var.aws_region
}

terraform {
  backend "s3" {
    bucket         = "infinia-tf-state-910424551974"
    key            = "infinia/state.tfstate"
    region         = "ap-southeast-2"
  }
}
