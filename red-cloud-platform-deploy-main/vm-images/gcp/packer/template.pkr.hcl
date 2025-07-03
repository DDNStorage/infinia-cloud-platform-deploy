variable "project_id" {
  type    = string
  default = "red-101"
}

variable "instance_type" {
  type    = string
  default = "n2-standard-2"
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "infinia_version" {
  default = "1.3.36"
}

variable "base_pkg_url" {
  default = "https://storage.googleapis.com/ddn-redsetup-public"
}

variable "release_type" {
  default = ""
}

variable "rel_dist_path" {
  default = "ubuntu/24.04"
}

packer {
  required_plugins {
    googlecompute = {
      version = ">= 0.3.0"
      source  = "github.com/hashicorp/googlecompute"
    }
  }
}

source "googlecompute" "infina" {
  image_name          = "infinia-${replace(var.infinia_version, ".", "-")}"
  machine_type        = var.instance_type
  zone                = "${var.region}-b"
  ssh_username        = "ubuntu"
  project_id          = var.project_id
  source_image_family = "ubuntu-2404-lts-amd64"

  disk_size = 256
  disk_type = "pd-ssd"
}

build {
  name    = "infina"
  sources = ["source.googlecompute.infina"]

  # provisioner "shell" {
  #   inline_shebang  = "/bin/bash"
  #   execute_command = "sudo -E bash -c '{{.Vars}}{{.Path}}'"
  #   inline = [
  #     "apt-get update && apt-get upgrade -y",
  #     "df -h",
  #     "reboot"
  #   ]
  # }

  provisioner "shell" {
    inline_shebang  = "/bin/bash"
    execute_command = "sudo -E bash -c '{{.Vars}}{{.Path}}'"
    expect_disconnect = true
    inline = [
      "export INFINIA_VERSION=${var.infinia_version}",
      "export BASE_PKG_URL=${var.base_pkg_url}",
      "export RELEASE_TYPE=${var.release_type}",
      "export REL_DIST_PATH=${var.rel_dist_path}",
      "export TARGET_ARCH=$(dpkg --print-architecture)",
      "export REL_PKG_URL=${var.base_pkg_url}/releases${var.release_type}/${var.rel_dist_path}",
      "export RED_VER=${var.infinia_version}",
      # "apt-get install -y lldpd",
      # "if systemctl list-units --type=service | grep -q lldpd.service; then systemctl enable lldpd && systemctl restart lldpd; else echo 'lldpd.service not found, skipping...'; fi",
      "wget ${var.base_pkg_url}/releases${var.release_type}/${var.rel_dist_path}/redsetup_${var.infinia_version}_$(dpkg --print-architecture)${var.release_type}.deb?cache-time=$(date +%s) -O /tmp/redsetup.deb",
      "apt install -y /tmp/redsetup.deb",
      "wget ${var.base_pkg_url}/releases/rmd_template.json -O /tmp/rmd_template.json",
      "envsubst < /tmp/rmd_template.json > /tmp/rmd.json",
      "redsetup -realm-entry -realm-entry-secret PA-ssW00r^d --admin-password PA-ssW00r^d -ctrl-plane-ip $(hostname --ip-address) -release-metadata-file /tmp/rmd.json -skip-reboot -skip-hardware-check",
      "redsetup -reset",
      "rm -rf /var/cache/apt /tmp/*",
      "apt-get autoremove -y && apt-get clean",
      "rm -rf /var/lib/apt/lists/*",
      "journalctl --rotate && journalctl --vacuum-time=1s",
      "rm -rf /var/log/* /tmp/* /var/tmp/*",
    ]
  }

  provisioner "shell" {
    inline_shebang  = "/bin/bash"
    execute_command = "sudo -E bash -c '{{.Vars}}{{.Path}}'"
    inline = [
      "truncate -s 0 /etc/machine-id",
      "truncate -s 0 /var/lib/dbus/machine-id",
      "ln -sf /etc/machine-id /var/lib/dbus/machine-id",
      "rm -rf /var/log/* /tmp/* /var/tmp/*",
      "touch /var/log/redsetup-complete"
    ]
  }
}
