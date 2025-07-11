provider "aws" {
  region = var.aws_region
}

terraform {
  backend "s3" {
    bucket = "infinia-tf-state-102800183015"
    key    = "infinia/state.tfstate"
    region = "ap-southeast-2"
  }
}
