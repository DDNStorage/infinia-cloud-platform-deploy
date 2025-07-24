terraform {
  backend "gcs" {
    bucket = "red-tf-state-bucket"
    prefix = "infinia/deployment_with_pd_gcp"
  }
}
