locals {
  instance_count = var.num_infinia_instances + 1
}

locals {
  user_startup_script_realm = <<EOT
#!/bin/bash
export INFINIA_VERSION="${var.infinia_version}"
export BASE_PKG_URL="https://storage.googleapis.com/ddn-redsetup-public"
export RELEASE_TYPE=""
export REL_DIST_PATH="ubuntu/24.04"
export TARGET_ARCH=$(dpkg --print-architecture)
export REL_PKG_URL="${var.base_pkg_url}/releases${var.release_type}/${var.rel_dist_path}"
LOG_COMPLETE="/etc/red/phase_one_compelete"
LOG_FILE="/tmp/log"
NODE_COUNT="${local.instance_count}"
rm /etc/machine-id && sudo systemd-machine-id-setup

log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

_check_inventory(){
     while true; do
        val1=$(redcli inventory show | grep Nodes | awk '{print $2}')
        val2=$(echo $NODE_COUNT )
        if [ "$val1" = "$val2" ]; then
            break
        else
            log_info "Waiting for nodes to join.."
            sleep 5
        fi
    done
}

if [ ! -f $LOG_COMPLETE ] ; then 
   apt-get update -y
   apt-get install -y lldpd
   systemctl list-units --type=service | grep -q lldpd.service  && systemctl enable lldpd  --now  | tee -a "$LOG_FILE"
   wget "${var.base_pkg_url}/releases${var.release_type}/${var.rel_dist_path}/redsetup_${var.infinia_version}_$(dpkg --print-architecture)${var.release_type}.deb?cache-time=$(date +%s)" -O /tmp/redsetup.deb
   apt install -y /tmp/redsetup.deb | tee  -a $LOG_FILE
   rm  -rf "/etc/red/deploy/config.lock" && redsetup -reset | tee -a $LOG_FILE || echo "Error running redsetup reset" | tee -a $LOG_FILE
   redsetup -realm-entry -realm-entry-secret 'PA-ssW00r^d' --admin-password 'PA-ssW00r^d' -ctrl-plane-ip $(hostname --ip-address)  -skip-reboot -skip-hardware-check | tee -a $LOG_FILE
   echo "reboot" |  tee -a $LOG_FILE
   touch $LOG_COMPLETE
   echo "rebooting" | tee -a $LOG_FILE
   reboot -f 
else 
  cd /tmp 
    redcli user login realm_admin -p 'PA-ssW00r^d'  | tee -a $LOG_FILE || echo "Error: redcli login failed" | tee -a "$LOG_FILE"
    redcli inventory show  | tee -a "$LOG_FILE"
    redcli realm config generate  || log_info "Error Generating config file" | tee -a "$LOG_FILE"
    _check_inventory
    #rm realm_config.yaml | log_info "removing old realm config"
    redcli realm config generate  || log_info "Error Generating config file" | tee -a "$LOG_FILE"
    redcli realm config update -f realm_config.yaml || log_info "Error updating realm"
    redcli license install -a '1DE94FE1-BE7D-4A4B-8DA2-7761ED7B66EA' -y | tee -a $LOG_FILE
    redcli cluster create c1 -S=false -z  -f   |  tee -a "$LOG_FILE" || echo "Error: failed to create cluster" | tee -a "$LOG_FILE"
    systemctl disable  cloudinit-rerun.service  --now
    rm -rf /var/lib/apt/lists/*
    journalctl --rotate && journalctl --vacuum-time=1s
    systemctl disable  cloudinit-rerun.service  --now
  fi
EOT
}

locals {
  user_startup_script_none_realm = <<EOT
#!/bin/bash
export INFINIA_VERSION="${var.infinia_version}"
export BASE_PKG_URL="https://storage.googleapis.com/ddn-redsetup-public"
export RELEASE_TYPE=""
export REL_DIST_PATH="ubuntu/24.04"
export TARGET_ARCH=$(dpkg --print-architecture)
export REL_PKG_URL="${var.base_pkg_url}/releases${var.release_type}/${var.rel_dist_path}"
LOG_COMPLETE="/etc/red/phase_one_compelete"
LOG_FILE="/tmp/log"
REALM_IP="${aws_instance.infinia_realm[0].private_ip}"
rm /etc/machine-id && sudo systemd-machine-id-setup
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

retry_curl() {
    local retry_count=0
    local max_attempts=$((15 * 60 / 10)) # 15 minutes with 10-second intervals
    local realm_entry=$1

    while [ $retry_count -lt $max_attempts ]; do
        log_info "Checking realm entry host: $realm_entry (Attempt $retry_count)"
        curl -k -s -o /tmp/curl_request.out https://$realm_entry:443/redsetup/v1/system/status
        if [ $? -eq 0 ]; then
            log_info "Success! Realm entry host is up."
            log_info "Waiting 120 seconds for stability..."
            sleep 130
            log_info "Rechecking realm entry host after 120 seconds."
            curl -k -s -o /tmp/curl_request.out https://$realm_entry:443/redsetup/v1/system/status
            if [ $? -eq 0 ]; then
                log_info "Realm entry host confirmed stable."
                return 0
            else
                log_info "Recheck failed. Retrying..."
            fi
        fi
        retry_count=$((retry_count + 1))
        sleep 10
    done

    log_info "Max retries reached. Exiting."
    exit 1
  }


if [ ! -f $LOG_COMPLETE ] ; then 
   apt-get update -y
   apt-get install -y lldpd
   systemctl list-units --type=service | grep -q lldpd.service  && systemctl enable lldpd  --now  | tee -a "$LOG_FILE"
   wget "${var.base_pkg_url}/releases${var.release_type}/${var.rel_dist_path}/redsetup_${var.infinia_version}_$(dpkg --print-architecture)${var.release_type}.deb?cache-time=$(date +%s)" -O /tmp/redsetup.deb
   apt install -y /tmp/redsetup.deb | tee  -a $LOG_FILE
   rm  -rf "/etc/red/deploy/config.lock" && redsetup -reset | tee -a $LOG_FILE || echo "Error running redsetup reset" | tee -a $LOG_FILE
   retry_curl $REALM_IP
   redsetup --realm-entry-address $REALM_IP --realm-entry-secret 'PA-ssW00r^d' -skip-reboot -skip-hardware-check
   echo "reboot" |  tee -a $LOG_FILE
   touch $LOG_COMPLETE
   echo "rebooting" | tee -a $LOG_FILE
   reboot -f 
 else 
   rm -rf /var/lib/apt/lists/*
   journalctl --rotate && journalctl --vacuum-time=1s
   systemctl disable  cloudinit-rerun.service  --now
    
fi 
EOT
}
