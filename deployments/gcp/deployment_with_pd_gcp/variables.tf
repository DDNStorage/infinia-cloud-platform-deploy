# Copyright 2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

variable "project_id" {
  description = "The ID of the project in which to provision resources."
  type        = string
  default     = "red-101"
}

// Marketplace requires this variable name to be declared
variable "goog_cm_deployment_name" {
  description = "The name of the deployment and VM instance."
  type        = string
  default     = "redtest"
}

variable "source_image" {
  description = "The image name for the disk for the VM instance."
  type        = string
  default     = "projects/ddn-public/global/images/ddn-infinia-2-0-23-ubuntu-2404-amd-2025-03-31"
}

variable "zone" {
  description = "The zone for the solution to be deployed."
  type        = string
  default     = "us-central1-a"
}

variable "machine_type" {
  description = "The machine type to create, e.g. n2d-standard-32  (Updating as a part of PD)"
  type        = string
  default     = "n2-standard-32"
}

variable "boot_disk_type" {
  description = "The boot disk type for the VM instance."
  type        = string
  default     = "pd-ssd"
}

variable "boot_disk_size" {
  description = "The boot disk size for the VM instance in GBs"
  type        = number
  default     = 256
}

variable "networks" {
  description = "The network name to attach the VM instance."
  type        = list(string)
  default     = ["default"]
}

variable "sub_networks" {
  description = "The sub network name to attach the VM instance."
  type        = list(string)
  default     = []
}

variable "external_ips" {
  description = "The external IPs assigned to the VM for public access."
  type        = list(string)
  default     = ["EPHEMERAL"]
}

variable "enable_tcp_443" {
  description = "Allow HTTPS traffic from the Internet"
  type        = bool
  default     = true
}

variable "tcp_443_source_ranges" {
  description = "Source IP ranges for HTTPS traffic"
  type        = string
  default     = ""
}

variable "httpsEnabled" {
  description = "Enabled HTTPS communication."
  type        = bool
  default     = true
}

variable "enable_cloud_logging" {
  description = "Enables Cloud Logging."
  type        = bool
  default     = false
}

variable "enable_cloud_monitoring" {
  description = "Enables Cloud Monitoring."
  type        = bool
  default     = false
}

variable "desired_capacity" {
  description = "Desired capacity in TB. Minimum is 63TB."
  type        = number
  default     = 63
}

variable "infinia_license" {
  description = "Optional Infinia license key for validation."
  type        = string
  default     = ""
}

variable "local_disks" {
  description = "The number of local disks to attach to each VM. Default is 24.  (Updating as a part of PD)"
  type        = number
  default     = 0
}

variable "pd_disk_count" {
  description = "Number of persistent disks per VM (Adding as a part of PD)"  
  type        = number
  default     = 24  # 8 persistent disks per VM
}

variable "pd_disk_size" {
  description = "Size of each persistent disk in GB (Adding as a part of PD)"
  type        = number
  default     = 375  # 500 GB per disk
}

variable "pd_disk_type" {
  description = "Type of persistent disk (Adding as a part of PD) "
  type        = string
  default     = "pd-ssd"  
}


variable "infinia_version" {
  type        = string
  default     = "2.0.23"
}

variable "num_clients" {
  description = "The number of client VM instances to create."
  type        = number
  default     = 0
}

variable "client_machine_type" {
  description = "The machine type for client VMs."
  type        = string
  default     = "n2d-standard-16"
}

variable "client_boot_disk_type" {
  description = "The boot disk type for client VM instances."
  type        = string
  default     = "pd-ssd"
}

variable "client_boot_disk_size" {
  description = "The boot disk size for client VM instances in GBs."
  type        = number
  default     = 100
}

variable "image_family" {
  description = "The image family to use for the VM instances"
  default     = "ubuntu-2404-lts-amd64"
}

variable "image_project" {
  description = "The GCP project hosting the image family"
  default     = "ubuntu-os-cloud"
}

variable "num_infinia_instances" {
  description = "The number of Infinia instances to create"
  type        = number
  default     = 6  # Default to 6 instances
}
