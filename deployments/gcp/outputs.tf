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

locals {
  # Get the network interface of the first instance
  first_network_interface = google_compute_instance.instances[0].network_interface[0]

  # Get the NAT IP or fallback to internal network IP of the first instance
  first_instance_nat_ip = length(local.first_network_interface.access_config) > 0 ? local.first_network_interface.access_config[0].nat_ip : null
  first_instance_ip     = coalesce(local.first_instance_nat_ip, local.first_network_interface.network_ip)

  # Get the machine type and zone (assume same for all instances)
  instance_machine_type = google_compute_instance.instances[0].machine_type
  instance_zone         = google_compute_instance.instances[0].zone

  client_machine_type = length(google_compute_instance.client_instances) > 0 ? google_compute_instance.client_instances[0].machine_type : null
  client_zone         = length(google_compute_instance.client_instances) > 0 ? google_compute_instance.client_instances[0].zone : null
}

output "site_url" {
  description = "Site URL of the first instance"
  value       = "https://${local.first_instance_ip}/"
}

output "realm_entry_secret" {
  description = "Password for realm entry."
  value       = random_password.realm_entry_secret.result
  sensitive   = true
}

output "admin_password" {
  description = "Password for admin."
  value       = random_password.admin_password.result
  sensitive   = true
}

output "first_instance_nat_ip" {
  description = "External NAT IP of the first compute instance."
  value       = local.first_instance_nat_ip
}

output "instance_machine_type" {
  description = "Machine type for all compute instances."
  value       = local.instance_machine_type
}

output "instance_zone" {
  description = "Zone for all compute instances."
  value       = local.instance_zone
}

output "instance_network" {
  description = "Network of the first compute instance."
  value       = var.networks[0]
}

output "total_capacity" {
  description = "Total capacity provisioned in TB."
  value       = local.vm_count * local.vm_capacity_tb
}

output "total_throughput" {
  description = "Total throughput provisioned in GB/s."
  value       = local.vm_count * 4
}

output "vm_count" {
  description = "Total number of VMs provisioned."
  value       = local.vm_count
}

