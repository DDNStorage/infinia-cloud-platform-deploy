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

provider "google" {
  project = var.project_id
}

locals {
  client_instance_names = [for i in range(var.num_clients) : "${var.goog_cm_deployment_name}-cn-${format("%03d", i)}"]

  # Calculate the required number of VMs based on desired capacity
  vm_capacity_tb = 9 # Each VM provides 9TB of capacity
  vm_count       = ceil(var.desired_capacity / local.vm_capacity_tb)

  # Generate instance names dynamically
  instance_names = [for i in range(local.vm_count) : "${var.goog_cm_deployment_name}-${format("%03d", i)}"]

  # Prepare network interfaces for each VM
  network_interfaces = [for i, n in var.networks : {
    network     = n,
    subnetwork  = length(var.sub_networks) > i ? element(var.sub_networks, i) : null
    external_ip = length(var.external_ips) > i ? element(var.external_ips, i) : "NONE"
  }]

  # Metadata for each VM instance
  metadata = {
    realm-entry-secret       = random_password.realm_entry_secret.result
    admin-password           = random_password.admin_password.result
    infinia-enable-https     = title(var.httpsEnabled)
    enable-os-login          = "TRUE"
    google-logging-enable    = var.enable_cloud_logging ? "1" : "0"
    google-monitoring-enable = var.enable_cloud_monitoring ? "1" : "0"
  }
}

# Create multiple VM instances dynamically
resource "google_compute_instance" "instances" {
  count = local.vm_count

  name         = local.instance_names[count.index]
  machine_type = var.machine_type
  zone         = var.zone

  # Enable deletion protection
  deletion_protection = var.project_id == "red-101" ? false : true

  # Configure scheduling for instances with local NVMe SSDs
  scheduling {
    automatic_restart   = true       # Automatically restart if terminated
    on_host_maintenance = "MIGRATE"  # Support live migration with Local SSDs
    preemptible         = false      # Ensures instance is not preemptible
    provisioning_model  = "STANDARD" # Standard VM for Local SSD support
  }

  tags = ["${var.goog_cm_deployment_name}-deployment"]

  # Configure boot disk
  boot_disk {
    device_name = "solution-vm-${count.index + 1}-boot-disk"

    initialize_params {
      size  = var.boot_disk_size
      type  = var.boot_disk_type
      image = var.source_image
    }
  }

  # Attach scratch disks for local SSDs
  dynamic "scratch_disk" {
    for_each = range(var.local_disks)
    content {
      interface = "NVME"
    }
  }

  metadata = merge(local.metadata, {
    infinia_version        = var.infinia_version
    infinia_license        = var.infinia_license
    startup-script-url     = "https://storage.cloud.google.com/infinia-hp-gcp-mp/startup-script.sh"
    infinia_instances      = join(",", local.instance_names)
    realm_entry_host       = local.instance_names[0]
    infinia_instance_count = tostring(local.vm_count)
    realm-entry-secret     = random_password.realm_entry_secret.result
    admin-password         = random_password.admin_password.result
  })

  # Configure network interfaces
  dynamic "network_interface" {
    for_each = local.network_interfaces
    content {
      network    = network_interface.value.network
      subnetwork = network_interface.value.subnetwork

      dynamic "access_config" {
        for_each = network_interface.value.external_ip == "NONE" ? [] : [1]
        content {
          nat_ip = network_interface.value.external_ip == "EPHEMERAL" ? null : network_interface.value.external_ip
        }
      }
    }
  }

  # Service account
  service_account {
    email = "default"
    scopes = compact([
      "https://www.googleapis.com/auth/cloud.useraccounts.readonly",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write"
    ])
  }
}

# Client VM Instances
resource "google_compute_instance" "client_instances" {
  count = var.num_clients

  name         = local.client_instance_names[count.index]
  machine_type = var.client_machine_type
  zone         = var.zone

  tags = ["${var.goog_cm_deployment_name}-client"]

  # Configure boot disk
  boot_disk {
    device_name = "client-vm-${count.index + 1}-boot-disk"

    initialize_params {
      size  = var.client_boot_disk_size
      type  = var.client_boot_disk_type
      image = "projects/${var.image_project}/global/images/family/${var.image_family}"
    }
  }

  metadata = {
    infinia_version       = var.infinia_version
    infinia_instance_type = "client"
  }

  # Configure network interfaces
  dynamic "network_interface" {
    for_each = local.network_interfaces
    content {
      network    = network_interface.value.network
      subnetwork = network_interface.value.subnetwork

      dynamic "access_config" {
        for_each = network_interface.value.external_ip == "NONE" ? [] : [1]
        content {
          nat_ip = network_interface.value.external_ip == "EPHEMERAL" ? null : network_interface.value.external_ip
        }
      }
    }
  }

  # Service account
  service_account {
    email = "default"
    scopes = compact([
      "https://www.googleapis.com/auth/cloud.useraccounts.readonly",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write"
    ])
  }
}

# Firewall rule for HTTPS traffic
resource "google_compute_firewall" "tcp_443" {
  count = var.enable_tcp_443 ? 1 : 0

  name    = "${var.goog_cm_deployment_name}-tcp-443"
  network = element(var.networks, 0)

  allow {
    ports    = ["443"]
    protocol = "tcp"
  }

  source_ranges = compact([for range in split(",", var.tcp_443_source_ranges) : trimspace(range)])

  target_tags = ["${var.goog_cm_deployment_name}-deployment"]
}

# Random password for realm entry
resource "random_password" "realm_entry_secret" {
  length  = 14
  special = false
}

# Random password for admin
resource "random_password" "admin_password" {
  length  = 14
  special = false
}
