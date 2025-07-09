locals {
  user_startup_script = <<EOT
#!/bin/bash
export INFINIA_VERSION="${var.infinia_version}"
export BASE_PKG_URL="https://storage.googleapis.com/ddn-redsetup-public"
export RELEASE_TYPE=""
export REL_DIST_PATH="ubuntu/24.04"
export TARGET_ARCH=$(dpkg --print-architecture)
export REL_PKG_URL="${var.base_pkg_url}/releases${var.release_type}/${var.rel_dist_path}"

apt-get update -y
apt-get install -y lldpd

if systemctl list-units --type=service | grep -q lldpd.service; then 
   systemctl enable lldpd && systemctl restart lldpd >> log
else 
     echo 'lldpd.service not found, skipping...'
fi

wget "${var.base_pkg_url}/releases${var.release_type}/${var.rel_dist_path}/redsetup_${var.infinia_version}_$(dpkg --print-architecture)${var.release_type}.deb?cache-time=$(date +%s)" -O /tmp/redsetup.deb
apt install -y /tmp/redsetup.deb >> /tmp/log

wget "${var.base_pkg_url}/releases/rmd_template.json" -O /tmp/rmd_template.json
envsubst < /tmp/rmd_template.json > /tmp/rmd.json

rm  -rf "/etc/red/deploy/config.lock"  && redsetup -reset >> /tmp/log || echo "Error running redsetup reset" >> log
redsetup -realm-entry -realm-entry-secret PA-ssW00r^d --admin-password PA-ssW00r^d -ctrl-plane-ip $(hostname --ip-address)  -skip-reboot -skip-hardware-check >> log
#redsetup -reset >> /tmp/log

rm -rf /var/lib/apt/lists/*
journalctl --rotate && journalctl --vacuum-time=1s
EOT
}

# SSM Document
resource "aws_ssm_document" "redsetup_script" {
  name          = "RunRedsetupScript"
  document_type = "Command"
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Run Redsetup configuration script"
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "runShellScript"
      inputs = {
        runCommand = [local.user_startup_script]
      }
    }]
  })
}



resource "null_resource" "trigger_redsetup" {
  count = var.num_infinia_instances
  triggers = {
    always_run = timestamp() # This ensures the null_resource is "changed" every time
  }

  provisioner "local-exec" {
    command     = <<EOF
      sleep 60 # Wait for ssm
      aws ssm send-command \
        --instance-ids ${aws_instance.infinia[count.index].id} \
        --document-name "${aws_ssm_document.redsetup_script.name}" \
        --comment "Triggered by Terraform apply for redsetup"
    EOF
    interpreter = ["bash", "-c"] # Or "powershell -command" on Windows

    environment = {
      AWS_DEFAULT_REGION = var.aws_region # Or retrieve from data source
    }
  }

  depends_on = [
    aws_instance.infinia,
    aws_ssm_document.redsetup_script
  ]
}

