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
  # Use the realm entry instance for the first network interface
  first_network_interface = google_compute_instance.realm_entry_instance.network_interface[0]
  
  # Get the NAT IP or fallback to internal network IP
  first_instance_nat_ip = length(local.first_network_interface.access_config) > 0 ? local.first_network_interface.access_config[0].nat_ip : null
  first_instance_ip     = coalesce(local.first_instance_nat_ip, local.first_network_interface.network_ip)
  
  # Combine all instances for machine type and zone references
  all_instances = concat([google_compute_instance.realm_entry_instance], google_compute_instance.follower_instances)
  
  instance_machine_type = google_compute_instance.realm_entry_instance.machine_type
  instance_zone         = google_compute_instance.realm_entry_instance.zone
}

output "site_url" {
  description = "Site Url"
  value       = "https://${local.first_instance_ip}"
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

output "instance_self_link" {
  description = "Self-link for the realm entry compute instance."
  value       = google_compute_instance.realm_entry_instance.self_link
}

output "instance_zone" {
  description = "Zone for the compute instance."
  value       = local.instance_zone
}

output "instance_nat_ip" {
  description = "External IP address of the first instance (or internal IP if no external IP)"
  value       = local.first_instance_ip
}

output "instance_network" {
  description = "Self-link for the network of the compute instance."
  value       = local.first_network_interface.network
}

output "instance_machine_types" {
  description = "Machine types for all compute instances."
  value = concat(
    [google_compute_instance.realm_entry_instance.machine_type],
    google_compute_instance.follower_instances[*].machine_type
  )
}

output "instance_nat_ips" {
  description = "List of all instance IPs (external if available, otherwise internal)"
  value = concat(
    [local.first_instance_ip],
    [for instance in google_compute_instance.follower_instances : 
      length(instance.network_interface[0].access_config) > 0 ? 
        instance.network_interface[0].access_config[0].nat_ip : 
        instance.network_interface[0].network_ip
    ]
  )
}

#output "total_capacity" {
#  description = "Total capacity provisioned in TB."
#  value       = local.vm_count * local.vm_capacity_tb
#}

#output "total_throughput" {
#  description = "Total throughput provisioned in GB/s."
#  value       = local.vm_count * 4
#}

output "vm_count" {
  description = "Total number of VMs provisioned."
  value       = var.num_infinia_instances
}
