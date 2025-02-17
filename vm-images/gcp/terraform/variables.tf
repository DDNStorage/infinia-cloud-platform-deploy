variable "infinia_version" {
  description = "Version of Infinia to install"
  type        = string
}

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "local_disks" {
  description = "Number of local NVMe disks to attach"
  type        = number
  default     = 24
}

variable "machine_type" {
  description = "Machine type for the VM instance"
  type        = string
  default     = "n2d-standard-32"
}

variable "zone" {
  description = "Zone where the instance will be created"
  type        = string
  default     = "us-central1-a"
}
