#!/bin/bash

# Constants
LOG_FILE="/var/log/infinia-deployment.log"
CREDENTIALS_FILE="/etc/infinia/initial-credentials.log"
METADATA_URL="http://metadata.google.internal/computeMetadata/v1"
INSTANCE_METADATA_URL="${METADATA_URL}/instance"
PROJECT_METADATA_URL="${METADATA_URL}/project"
ATTRIBUTES_METADATA_URL="${METADATA_URL}/instance/attributes"
METADATA_FLAVOR_HEADER="Metadata-Flavor: Google"
FLAG_FILE="/etc/infinia/deployment_flag"

sudo mkdir -p /etc/infinia
sudo touch "$FLAG_FILE"
sudo chmod 666 "$LOG_FILE"

# Logging function
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Check inventory
check_inventory(){
    while true; do
    val1=$(redcli inventory show | grep Nodes | awk '{print $2}')
    val2=$(echo $NODE_COUNT )
    if [ "$val1" = "$val2" ]; then
        break
    else
        log_info "Waiting for nodes to join.."
        sleep 1
    fi
done
}

fetch_metadata() {
    local url=$1
    curl -s -H "${METADATA_FLAVOR_HEADER}" "$url" || { log_info "Error fetching metadata: $url"; exit 1; }
}

# Function to check if script is running after reboot
is_after_reboot() {
    grep -q "AFTER_REBOOT" "$FLAG_FILE" && return 0 || return 1
}

# Function to mark script as after reboot
mark_after_reboot() {
    echo "AFTER_REBOOT" | sudo tee "$FLAG_FILE"
}

# Retry function for realm entry host readiness
retry_curl() {
    local retry_count=0
    local max_attempts=$((15 * 60 / 10)) # 15 minutes with 10-second intervals
    local realm_entry=$1

    while [ $retry_count -lt $max_attempts ]; do
        log_info "Checking realm entry host: $realm_entry (Attempt $retry_count)"
        curl -k -s -o /tmp/curl_request.out https://${realm_entry}:443/redsetup/v1/system/status
        if [ $? -eq 0 ]; then
            log_info "Success! Realm entry host is up."
            log_info "Waiting 120 seconds for stability..."
            sleep 120
            log_info "Rechecking realm entry host after 120 seconds."
            curl -k -s -o /tmp/curl_request.out https://${realm_entry}:443/redsetup/v1/system/status
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

# Function to check Infinia instance count
check_infinia_instance_count() {
    local expected_count=$1
    for i in {1..20}; do
        local count=$(redcli inventory show --output-format json | jq '.data.nodes | length')
        log_info "Current INFINIA_INSTANCE_COUNT: $count (Attempt $i)"
        [ "$count" -eq "$expected_count" ] && return 0
        sleep 30
    done
    log_info "INFINIA_INSTANCE_COUNT did not match after retries."
    exit 1
}


# Function to validate and activate license
validate_and_activate_license() {
    local license=$1

    if [ -n "$license" ]; then
        log_info "License provided. Activating license..."
        redcli user login realm_admin -p "$ADMIN_PASSWORD"
        check_inventory 
        redcli realm config generate
        redcli realm config update -f realm_config.yaml
        redcli license install -a "$license" -y
        redcli cluster create c1 -S=false -z  -f
        if [ $? -eq 0 ]; then
            log_info "License activated successfully."
        else
            log_info "Failed to activate the license. Exiting."
        fi
    else
        log_info "No license provided. Skipping license activation."
    fi
}

# Main script
log_info "Starting Infinia deployment script..."

if is_after_reboot; then
    log_info "Running after reboot sequence..."
    REALM_ENTRY_HOST=$(fetch_metadata "${ATTRIBUTES_METADATA_URL}/realm_entry_host")
    ADMIN_PASSWORD=$(fetch_metadata "${ATTRIBUTES_METADATA_URL}/admin-password")
    INFINIA_INSTANCE_COUNT=$(fetch_metadata "${ATTRIBUTES_METADATA_URL}/infinia_instance_count")
    CURRENT_INSTANCE=$(fetch_metadata "${INSTANCE_METADATA_URL}/name")
    INFINIA_LICENSE=$(fetch_metadata "${ATTRIBUTES_METADATA_URL}/infinia_license")

    if [ "$(fetch_metadata "${INSTANCE_METADATA_URL}/name")" == "$REALM_ENTRY_HOST" ]; then
        log_info "Checking Infinia instance count on realm entry node..."
        redcli user login realm_admin -p "$ADMIN_PASSWORD"
        check_infinia_instance_count "$INFINIA_INSTANCE_COUNT"
        
    fi

    if [ "$CURRENT_INSTANCE" == "$REALM_ENTRY_HOST" ]; then
        validate_and_activate_license "$INFINIA_LICENSE"

    fi

    log_info "Disabling google-startup-scripts.service..."
    sudo systemctl disable google-startup-scripts.service
    sudo systemctl stop google-startup-scripts.service
    log_info "Startup script disabled successfully."

    exit 0
fi

# Fetch metadata values
REALM_ENTRY_HOST=$(fetch_metadata "${ATTRIBUTES_METADATA_URL}/realm_entry_host")
REALM_ENTRY_SECRET=$(fetch_metadata "${ATTRIBUTES_METADATA_URL}/realm-entry-secret")
ADMIN_PASSWORD=$(fetch_metadata "${ATTRIBUTES_METADATA_URL}/admin-password")
INFINIA_VERSION=$(fetch_metadata "${ATTRIBUTES_METADATA_URL}/infinia_version")

CURRENT_INSTANCE=$(fetch_metadata "${INSTANCE_METADATA_URL}/name")
log_info "CURRENT_INSTANCE: $CURRENT_INSTANCE"

# Store credentials securely
log_info "Storing initial credentials in $CREDENTIALS_FILE..."
sudo mkdir -p "$(dirname $CREDENTIALS_FILE)"
sudo bash -c "cat << EOF > $CREDENTIALS_FILE
# Initial credentials for Infinia deployment
# Please change these credentials immediately after deployment.
$(date '+%Y-%m-%d %H:%M:%S') - REALM_ENTRY_SECRET: $REALM_ENTRY_SECRET
$(date '+%Y-%m-%d %H:%M:%S') - ADMIN_PASSWORD: $ADMIN_PASSWORD
EOF"
sudo chmod 600 $CREDENTIALS_FILE
log_info "Initial credentials stored securely. Please change them immediately and delete the file."

# Clear and reset machine-id (only before reboot)
log_info "Resetting machine-id before running redsetup..."
sudo rm /etc/machine-id && sudo systemd-machine-id-setup

if [ "$CURRENT_INSTANCE" == "$REALM_ENTRY_HOST" ]; then
    log_info "Configuring Realm Entry Host..."

    export BASE_PKG_URL="https://storage.googleapis.com/ddn-redsetup-public"
    export RELEASE_TYPE=""
    export TARGET_ARCH="$(dpkg --print-architecture)"
    export REL_DIST_PATH="ubuntu/24.04"
    export RED_VER="$INFINIA_VERSION"

    wget $BASE_PKG_URL/releases/rmd_template.json -O /tmp/rmd_template.json
    envsubst < /tmp/rmd_template.json > /tmp/rmd.json

    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    sudo redsetup -realm-entry \
        -realm-entry-secret "$REALM_ENTRY_SECRET" \
        --admin-password "$ADMIN_PASSWORD" \
        -ctrl-plane-ip "$IP_ADDRESS" \
        -release-metadata-file /tmp/rmd.json \
        -skip-reboot

    log_info "Realm Entry Host configuration completed."
else
    log_info "Waiting for Realm Entry Host to be ready..."
    retry_curl "$REALM_ENTRY_HOST"

    log_info "Configuring Non-Realm Entry Host..."
    sudo redsetup --realm-entry-address "$REALM_ENTRY_HOST" --realm-entry-secret "$REALM_ENTRY_SECRET" -skip-reboot
    log_info "Non-Realm Entry Host configuration completed."
fi

log_info "Marking for after reboot..."
mark_after_reboot

log_info "Rebooting the system..."
sudo reboot
