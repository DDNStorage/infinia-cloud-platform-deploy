


locals {
  infinia_instance_names = [for i in range(var.num_infinia_instances) : "infinia-${i}"]
  realm_instance         = local.infinia_instance_names[0]
}


locals {
  user_startup_script = <<EOT
#!/bin/bash
export INFINIA_VERSION="${var.infinia_version}"
export BASE_PKG_URL="https://storage.googleapis.com/ddn-redsetup-public"
export RELEASE_TYPE=""
export REL_DIST_PATH="ubuntu/24.04"
export TARGET_ARCH=$(dpkg --print-architecture)
export REL_PKG_URL="${var.base_pkg_url}/releases${var.release_type}/${var.rel_dist_path}"
LOG_COMPLETE="/etc/red/phase_one_compelete"
LOG_FILE="/tmp/log"
IS_REALM=$(echo "${local.realm_instance}" >> /etc/red/is_realm)

if [ ! -f $LOG_COMPLETE ] ; then 
   apt-get update -y
   apt-get install -y lldpd net-tools dnsutils
   systemctl list-units --type=service | grep -q lldpd.service  && systemctl enable lldpd  --now  | tee -a "$LOG_FILE"
   wget "${var.base_pkg_url}/releases${var.release_type}/${var.rel_dist_path}/redsetup_${var.infinia_version}_$(dpkg --print-architecture)${var.release_type}.deb?cache-time=$(date +%s)" -O /tmp/redsetup.deb
   apt install -y /tmp/redsetup.deb | tee  -a $LOG_FILE
   rm  -rf "/etc/red/deploy/config.lock" && redsetup -reset | tee -a $LOG_FILE || echo "Error running redsetup reset" | tee -a $LOG_FILE
  if [ -f $IS_REALM ]; then
   export REALM_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
   redsetup -realm-entry -realm-entry-secret 'PA-ssW00r^f' --admin-password PA-ssW-01r^f -ctrl-plane-ip $(hostname --ip-address)  -skip-reboot -skip-hardware-check | tee -a $LOG_FILE
  else 
     
     redsetup --realm-entry-address "$REALM_IP" --realm-entry-secret PA-ssW00r^f -skip-reboot
  fi
    echo "reboot" |  tee -a $LOG_FILE
    touch $LOG_COMPLETE
    rm -rf /var/lib/apt/lists/*
    journalctl --rotate && journalctl --vacuum-time=1s
    echo "rebooting" | tee -a $LOG_FILE
    reboot 
else 
  cd /tmp 
    redcli user login realm_admin -p PA-ssW00r^f  | tee -a $LOG_FILE || echo "Error: redcli login failed" | tee -a "$LOG_FILE"
    sleep 10
    redcli inventory show && redcli realm config generate | tee -a "$LOG_FILE" || echo "Error: redcli config generate failed" tee -a $LOG_FILE
    redcli realm config update -f realm_config.yaml | tee -a "$LOG_FILE" || echo "Error: redcli config update failed" | tee -a "$LOG_FILE"
    redcli license install -a '1DE94FE1-BE7D-4A4B-8DA2-7761ED7B66EA' -y | tee -a $LOG_FILE
    redcli cluster create c1 -S=false -z  |  tee -a "$LOG_FILE" || echo "Error: failed to create cluster" | tee -a "$LOG_FILE"
    systemctl disable  cloudinit-rerun.service  --now
  fi
EOT
}
