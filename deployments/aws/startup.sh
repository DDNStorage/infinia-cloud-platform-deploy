#!/bin/bash
export INFINIA_VERSION="${infinia_version}"
export BASE_PKG_URL="https://storage.googleapis.com/ddn-redsetup-public"
export RELEASE_TYPE=""
export REL_DIST_PATH="ubuntu/24.04"
export TARGET_ARCH=$(dpkg --print-architecture)
LOG_COMPLETE="/etc/red/phase_one_compelete"
LOG_FILE="/tmp/log"
IS_RELAM="${is_realm}"

log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}
rm /etc/machine-id && sudo systemd-machine-id-setup
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
            sleep 120
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
   wget "$BASE_PKG_URL/releases/$RELEASE_TYPE/$REL_DIST_PATH/redsetup_$INFINIA_VERSION_$(dpkg --print-architecture)$RELEASE_TYPE.deb?cache-time=$(date +%s)" -O /tmp/redsetup.deb
   apt install -y /tmp/redsetup.deb | tee  -a $LOG_FILE
   rm  -rf "/etc/red/deploy/config.lock" && redsetup -reset | tee -a $LOG_FILE || echo "Error running redsetup reset" | tee -a $LOG_FILE
   if IS_RELAM; then
        redsetup -realm-entry -realm-entry-secret 'PA-ssW00r^d' --admin-password 'PA-ssW00r^d' -ctrl-plane-ip $(hostname --ip-address)  -skip-reboot  | tee -a $LOG_FILE
   else 
      retry_curl $REALM_IP
      redsetup --realm-entry-address $REALM_IP --realm-entry-secret 'PA-ssW00r^d' -skip-reboot
      touch $LOG_COMPLETE
  fi
  rm -rf /var/lib/apt/lists/*
  journalctl --rotate && journalctl --vacuum-time=1s
  echo "reboot" |  tee -a $LOG_FILE
  reboot 

      echo "rebooting" | tee -a $LOG_FILE
else 
  cd /tmp 
    redcli user login realm_admin -p 'PA-ssW00r^d'  | tee -a $LOG_FILE || echo "Error: redcli login failed" | tee -a "$LOG_FILE"
    sleep 10
    redcli inventory show && redcli realm config generate | tee -a "$LOG_FILE" || echo "Error: redcli config generate failed" tee -a $LOG_FILE
    redcli realm config update -f realm_config.yaml | tee -a "$LOG_FILE" || echo "Error: redcli config update failed" | tee -a "$LOG_FILE"
    redcli license install -a '1DE94FE1-BE7D-4A4B-8DA2-7761ED7B66EA' -y | tee -a $LOG_FILE
    redcli cluster create c1 -S=false -z -m 0  |  tee -a "$LOG_FILE" || echo "Error: failed to create cluster" | tee -a "$LOG_FILE"
    systemctl disable  cloudinit-rerun.service  --now
  fi

