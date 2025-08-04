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

data "google_compute_subnetwork" "secure_subnet" {
  name   = var.secure_subnet_name
  region = var.region
}

locals {
  client_instance_names = [for i in range(var.num_clients) : "${var.goog_cm_deployment_name}-cn-${format("%03d", i)}"]

  # Calculate the required number of VMs based on desired capacity
  vm_capacity_tb = 9 # Each VM provides 9TB of capacity
  vm_count       = ceil(var.desired_capacity / local.vm_capacity_tb)

  # Generate instance names dynamically
  #  instance_names = [for i in range(local.vm_count) : "${var.goog_cm_deployment_name}-${format("%01d", i)}"]
  instance_names = [for i in range(var.num_infinia_instances) : "${var.goog_cm_deployment_name}-${format("%01d", i)}"]

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



# First, create the realm entry node (first instance)
resource "google_compute_instance" "realm_entry_instance" {
  name         = "${var.goog_cm_deployment_name}-0"
  machine_type = var.machine_type
  zone         = var.zone

  # Enable deletion protection
  deletion_protection = false

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
    device_name = "solution-vm-1-boot-disk"

    initialize_params {
      size  = var.boot_disk_size
      type  = "pd-ssd" #var.boot_disk_type
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
    startup-script-url     = "https://storage.googleapis.com/infinia-hp-gcp-mp/dev-startup-script.sh"
    infinia_instances      = join(",", local.instance_names)
    realm_entry_host       = "${var.goog_cm_deployment_name}-0"
    infinia_instance_count = tostring(var.num_infinia_instances)
    pd_disk_count          = tostring(var.pd_disk_count)
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

  network_interface {
    subnetwork = data.google_compute_subnetwork.secure_subnet.self_link
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

# Add a time delay to ensure the first instance is fully initialized
resource "time_sleep" "wait_for_realm_entry" {
  depends_on = [google_compute_instance.realm_entry_instance]

  # Wait for 10 minutes to ensure the realm entry node is fully set up
  create_duration = "10m"
}

# Create the remaining instances after the wait period
resource "google_compute_instance" "follower_instances" {
  count = var.num_infinia_instances - 1 # Subtract 1 for the realm entry instance

  # Ensure these instances are created only after the wait period
  depends_on = [time_sleep.wait_for_realm_entry]

  name         = "${var.goog_cm_deployment_name}-${count.index + 1}"
  machine_type = var.machine_type
  zone         = var.zone

  # Enable deletion protection
  deletion_protection = false

  # Configure scheduling for instances with local NVMe SSDs
  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
    provisioning_model  = "STANDARD"
  }

  tags = ["${var.goog_cm_deployment_name}-deployment"]

  # Configure boot disk
  boot_disk {
    device_name = "solution-vm-${count.index + 2}-boot-disk"

    initialize_params {
      size  = var.boot_disk_size
      type  = "pd-ssd"
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
    startup-script-url     = "https://storage.googleapis.com/infinia-hp-gcp-mp/dev-startup-script.sh"
    infinia_instances      = join(",", local.instance_names)
    realm_entry_host       = "${var.goog_cm_deployment_name}-0"
    infinia_instance_count = tostring(var.num_infinia_instances)
    pd_disk_count          = tostring(var.pd_disk_count)
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

  network_interface {
    subnetwork = data.google_compute_subnetwork.secure_subnet.self_link
  }

  # Service account
  service_account {
    email = "default"
    scopes = compact([
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write"
    ])
  }
}

# Client VM Instances
resource "google_compute_instance" "client_instances" {
  count = var.num_clients

  # Create clients after all infinia instances are ready
  depends_on = [
    google_compute_instance.realm_entry_instance,
    google_compute_instance.follower_instances
  ]

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
    realm_entry_host      = "${var.goog_cm_deployment_name}-0"
    realm-entry-secret    = random_password.realm_entry_secret.result
    admin-password        = random_password.admin_password.result
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

# Create persistent disks for all instances first
resource "google_compute_disk" "infinia_data_disks" {
  count = var.num_infinia_instances * var.pd_disk_count

  name = "${var.goog_cm_deployment_name}-pd-${floor(count.index / var.pd_disk_count)}-${count.index % var.pd_disk_count}"
  type = var.pd_disk_type
  zone = var.zone
  size = var.pd_disk_size
}

# Attach disks to the realm entry instance
resource "google_compute_attached_disk" "realm_entry_attached_disks" {
  count    = var.pd_disk_count
  disk     = google_compute_disk.infinia_data_disks[count.index].id
  instance = google_compute_instance.realm_entry_instance.id
}

# Attach disks to the follower instances
resource "google_compute_attached_disk" "follower_attached_disks" {
  count    = (var.num_infinia_instances - 1) * var.pd_disk_count
  disk     = google_compute_disk.infinia_data_disks[count.index + var.pd_disk_count].id
  instance = google_compute_instance.follower_instances[floor(count.index / var.pd_disk_count)].id
}

# Remove or comment out the old data_disks and attached_data_disks resources
# resource "google_compute_disk" "data_disks" { ... }
# resource "google_compute_attached_disk" "attached_data_disks" { ... }
