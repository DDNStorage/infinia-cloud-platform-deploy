provider "google" {
  project = var.project_id
  region  = "us-central1"
}

resource "google_compute_instance" "infinia_vm" {
  name         = "infinia-${replace(var.infinia_version, ".", "-")}"
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2404-lts-amd64"
      size  = 256
      type  = "pd-ssd"
    }
  }

  # Attach scratch disks for local SSDs
  dynamic "scratch_disk" {
    for_each = range(var.local_disks)
    content {
      interface = "NVME"
    }
  }

  metadata = {
    INFINIA_VERSION = var.infinia_version
    startup-script = <<EOT
#!/bin/bash
INFINIA_VERSION=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/attributes/INFINIA_VERSION -H "Metadata-Flavor: Google")
export BASE_PKG_URL="https://storage.googleapis.com/ddn-redsetup-public"
export RELEASE_TYPE=""
export TARGET_ARCH="$(dpkg --print-architecture)"
export REL_DIST_PATH="ubuntu/24.04"
export REL_PKG_URL="$${BASE_PKG_URL}/releases$${RELEASE_TYPE}/$${REL_DIST_PATH}"
export RED_VER=$${INFINIA_VERSION}
wget $${REL_PKG_URL}/redsetup_"$${RED_VER}"_"$${TARGET_ARCH}$${RELEASE_TYPE}".deb?cache-time="$(date +%s)" -O /tmp/redsetup.deb
sudo apt install -y /tmp/redsetup.deb
wget $${BASE_PKG_URL}/releases/rmd_template.json -O /tmp/rmd_template.json
envsubst < /tmp/rmd_template.json > /tmp/rmd.json
sudo redsetup -realm-entry -realm-entry-secret PA-ssW00r^d --admin-password PA-ssW00r^d -ctrl-plane-ip $(hostname --ip-address) -release-metadata-file /tmp/rmd.json -skip-reboot
sudo redsetup -reset

# Signal completion
touch /var/log/startup-complete
EOT
  }


  network_interface {
    network = "default"
    access_config {}
  }
}

resource "null_resource" "wait_for_startup" {
  provisioner "local-exec" {
    command = <<EOT
while ! gcloud compute ssh ${google_compute_instance.infinia_vm.name} \
  --zone ${google_compute_instance.infinia_vm.zone} \
  --command "test -f /var/log/startup-complete"; do
  echo "Waiting for startup script to complete..."
  sleep 10
done
EOT
  }

  depends_on = [google_compute_instance.infinia_vm]
}

resource "null_resource" "create_image" {
  provisioner "local-exec" {
    command = <<EOT
gcloud compute instances stop ${google_compute_instance.infinia_vm.name} --zone ${google_compute_instance.infinia_vm.zone} --discard-local-ssd=true &&
gcloud compute images create ddn-infinia-${replace(var.infinia_version, ".", "-")}-ubuntu-2404-amd-$(date +%Y-%m-%d) \
  --source-disk ${google_compute_instance.infinia_vm.name} \
  --source-disk-zone ${google_compute_instance.infinia_vm.zone} \
  --licenses projects/ddn-public/global/licenses/cloud-marketplace-546f824325b15ca6-df1ebeb69c0ba664 \
  --family ddn-infinia-ubuntu-2404-lts-amd64 \
  --description "${var.infinia_version}" &&
gcloud compute images add-iam-policy-binding ddn-infinia-${replace(var.infinia_version, ".", "-")}-ubuntu-2404-amd-$(date +%Y-%m-%d) \
  --member allAuthenticatedUsers --role roles/compute.imageUser
EOT
  }

  depends_on = [null_resource.wait_for_startup]
}
