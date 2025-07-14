locals {
  cloud_init_user_data = <<EOT
#cloud-config
runcmd:
  - |
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
        systemctl enable lldpd && systemctl restart lldpd >> /var/log/cloud-init-output.log
      else
        echo 'lldpd.service not found, skipping...' >> /var/log/cloud-init-output.log
      fi

      wget "${var.base_pkg_url}/releases${var.release_type}/${var.rel_dist_path}/redsetup_${var.infinia_version}_$(dpkg --print-architecture)${var.release_type}.deb?cache-time=$(date +%s)" -O /tmp/redsetup.deb
      apt install -y /tmp/redsetup.deb >> /var/log/cloud-init-output.log

      rm -rf "/etc/red/deploy/config.lock" && redsetup -reset >> /var/log/cloud-init-output.log || echo "Error running redsetup reset || config.lock dose not exists" >> /var/log/cloud-init-output.log
      redsetup -realm-entry -realm-entry-secret 'PA-ssW00r^d' --admin-password 'PA-ssW00r^d' -ctrl-plane-ip $(hostname --ip-address) -skip-reboot  >> /var/log/cloud-init-output.log
      echo "rebooting" >> /var/log/cloud-init-output.log
      reboot 

    rm -rf /var/lib/apt/lists/*
    journalctl --rotate && journalctl --vacuum-time=1s
EOT
}


locals {
  cluster_config = <<EOF
    cd /tmp 
    redcli user login realm_admin -p 'PA-ssW00r^d' >> /var/log/cloud-init-output.log || echo "Error: redcli login failed" >> /var/log/cloud-init-output.log
    redcli inventory show  >> /var/log/cloud-init-output.log || echo "Error: no inventory" >> /var/log/cloud-init-output.log
    redcli realm config generate >> /var/log/cloud-init-output.log || echo "Error: redcli config generate failed" >> /var/log/cloud-init-output.log
    redcli realm config update -f /tmp/realm_config.yaml >> /var/log/cloud-init-output.log || echo "Error: redcli config update failed" >> /var/log/cloud-init-output.log
    redcli license install -a 1DE94FE1-BE7D-4A4B-8DA2-7761ED7B66EA -y >> /var/log/cloud-init-output.log
    redcli cluster create c1 -S=false -z  >> /var/log/cloud-init-output.log || echo "Error: failed to create cluster" >> /var/log/cloud-init-output.log
EOF


}

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
        runCommand = [local.cluster_config]
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
    #sleep 30# Wait for node boot
      aws ssm send-command \
        --instance-ids ${aws_instance.infinia[count.index].id} \
        --document-name "${aws_ssm_document.redsetup_script.name}" \
        --comment "Triggered by Terraform apply for redsetup"
    EOF
    interpreter = ["bash", "-c"]

    environment = {
      AWS_DEFAULT_REGION = var.aws_region
    }
  }

  depends_on = [
    aws_instance.infinia,
    aws_ssm_document.redsetup_script
  ]
}



