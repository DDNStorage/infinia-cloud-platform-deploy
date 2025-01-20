variable "instance_type" {
  type    = string
  default = "t2.medium"
}

variable "region" {
  type    = string
  default = "us-east-2"
}

variable "infinia_version" {
  default = "1.3.38"
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
    amazon = {
      version = ">= 1.3.4"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "infina" {
  ami_name                    = "infinia-${replace(var.infinia_version, ".", "-")}"
  instance_type               = var.instance_type
  region                      = var.region
  ssh_username                = "ubuntu"
  associate_public_ip_address = true

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/*ubuntu-noble-24.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"]
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 256
    volume_type           = "gp3"
    delete_on_termination = true
  }
}

build {
  name    = "infina"
  sources = ["source.amazon-ebs.infina"]

  provisioner "shell" {
    inline_shebang  = "/bin/bash"
    execute_command = "sudo -E bash -c '{{.Vars}}{{.Path}}'"
    inline = [
      "apt-get update && apt-get upgrade -y",
      "df -h",
      "reboot"
    ]
  }

  provisioner "shell" {
    inline_shebang  = "/bin/bash"
    execute_command = "sudo -E bash -c '{{.Vars}}{{.Path}}'"
    inline = [
      "export INFINIA_VERSION=${var.infinia_version}",
      "export BASE_PKG_URL=${var.base_pkg_url}",
      "export RELEASE_TYPE=${var.release_type}",
      "export REL_DIST_PATH=${var.rel_dist_path}",
      "export TARGET_ARCH=$(dpkg --print-architecture)",
      "export REL_PKG_URL=${var.base_pkg_url}/releases${var.release_type}/${var.rel_dist_path}",
      "export RED_VER=${var.infinia_version}",
      "apt-get install -y lldpd",
      "if systemctl list-units --type=service | grep -q lldpd.service; then systemctl enable lldpd && systemctl restart lldpd; else echo 'lldpd.service not found, skipping...'; fi",
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
      "touch /var/log/redsetup-complete"
    ]
  }

  provisioner "shell" {
    inline_shebang  = "/bin/bash"
    execute_command = "sudo -E bash -c '{{.Vars}}{{.Path}}'"
    inline = [
      "sudo bash -c 'cat <<EOF > /etc/systemd/system/regenerate-machine-id.service
[Unit]
Description=Regenerate machine-id on boot
Before=network-pre.target
Wants=network-pre.target
ConditionPathExists=!/etc/machine-id

[Service]
Type=oneshot
ExecStart=/bin/rm -f /etc/machine-id /var/lib/dbus/machine-id
ExecStart=/bin/systemd-machine-id-setup
ExecStart=/bin/ln -sf /etc/machine-id /var/lib/dbus/machine-id
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF'",

      "sudo systemctl daemon-reload",
      "sudo systemctl enable regenerate-machine-id.service",
      "sudo touch /etc/cloud/cloud-init.disabled"
    ]
  }
}
