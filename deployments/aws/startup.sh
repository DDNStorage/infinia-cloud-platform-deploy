#!/bin/bash

# Constants
LOG_FILE="/var/log/infinia-deployment.log"
CREDENTIALS_FILE="/etc/infinia/initial-credentials.log"
# AWS metadata service endpoint
METADATA_URL="http://169.254.169.254/latest/meta-data"
FLAG_FILE="/etc/infinia/deployment_flag"

sudo mkdir -p /etc/infinia
sudo touch "$FLAG_FILE"
sudo chmod 666 "$LOG_FILE" # Ensure log file is writable by all, for easier debugging if permissions are tricky

# Logging function
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to fetch instance metadata (AWS EC2 User Data can replace some of this)
# For user-data passed variables, we'll use environment variables set by Terraform
# rather than fetching from metadata directly in the script for simplicity.
# However, fetching instance ID/name from IMDS is useful.
fetch_aws_metadata() {
    local path=$1
    curl -s "$METADATA_URL/$path" || { log_info "Error fetching AWS metadata: $path"; exit 1; }
}

# Function to check if script is running after reboot
is_after_reboot() {
    grep -q "AFTER_REBOOT" "$FLAG_FILE" && return 0 || return 1
}

# Function to mark script as after reboot
mark_after_reboot() {
    echo "AFTER_REBOOT" | sudo tee "$FLAG_FILE" # Added sudo before tee
}

# Retry function for realm entry host readiness
retry_curl() {
    local retry_count=0
    local max_attempts=$((15 * 60 / 10)) # 15 minutes with 10-second intervals
    local realm_entry=$1

    while [ $retry_count -lt $max_attempts ]; do
        log_info "Checking realm entry host: $realm_entry (Attempt $retry_count)"
        # Using -k for insecure curl, adjust if you have proper certs
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
        # Assuming redcli is installed and configured
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
        redcli realm config generate
        redcli realm config update -f realm_config.yaml
        redcli license install -a "$license" -y
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

# Variables will be passed as environment variables via Terraform user data
# REALM_ENTRY_HOST, REALM_ENTRY_SECRET, ADMIN_PASSWORD, INFINIA_VERSION, INFINIA_INSTANCE_COUNT, INFINIA_LICENSE

# Fetch instance ID (can be used as a unique identifier if a custom 'name' isn't set)
INSTANCE_ID=$(fetch_aws_metadata "instance-id")
# You might want to pass a 'name' tag from Terraform to differentiate instances
# If you need the instance name, you'd fetch it from the tags:
# INSTANCE_NAME=$(curl -s http://169.254.169.254/latest/meta-data/tags/instance/Name)
# For simplicity, we'll assume REALM_ENTRY_HOST is the actual hostname or IP

# Determine if this instance is the Realm Entry Host based on a passed variable
IS_REALM_ENTRY_HOST_INSTANCE="false"
if [ "$INSTANCE_ID" == "$REALM_ENTRY_INSTANCE_ID" ]; then # Assuming you pass the ID of the realm entry instance
    IS_REALM_ENTRY_HOST_INSTANCE="true"
    log_info "This instance is the Realm Entry Host."
else
    log_info "This instance is a Non-Realm Entry Host."
fi

if is_after_reboot; then
    log_info "Running after reboot sequence..."

    # The variables are already available from the initial user data execution
    # REALM_ENTRY_HOST, ADMIN_PASSWORD, INFINIA_INSTANCE_COUNT, INFINIA_LICENSE, IS_REALM_ENTRY_HOST_INSTANCE

    if [ "$IS_REALM_ENTRY_HOST_INSTANCE" == "true" ]; then
        log_info "Checking Infinia instance count on realm entry node..."
        # Ensure redcli is available in the PATH or provide full path
        redcli user login realm_admin -p "$ADMIN_PASSWORD"
        check_infinia_instance_count "$INFINIA_INSTANCE_COUNT"
    fi

    if [ "$IS_REALM_ENTRY_HOST_INSTANCE" == "true" ]; then
        validate_and_activate_license "$INFINIA_LICENSE"
    fi

    # No google-startup-scripts.service on AWS, so this part is removed.
    log_info "After reboot sequence completed."
    exit 0
fi

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

# Clear and reset machine-id (common for many Linux systems, not AWS specific)
log_info "Resetting machine-id before running redsetup..."
sudo rm -f /etc/machine-id && sudo systemd-machine-id-setup

if [ "$IS_REALM_ENTRY_HOST_INSTANCE" == "true" ]; then
    log_info "Configuring Realm Entry Host..."

    # These URLs might need to be adjusted for AWS environment or Infinia's AWS deployment
    export BASE_PKG_URL="https://storage.googleapis.com/ddn-redsetup-public" # This is a GCS URL, may need to be S3 or a custom location
    export RELEASE_TYPE=""
    export TARGET_ARCH="$(dpkg --print-architecture)"
    export REL_DIST_PATH="ubuntu/24.04"
    export RED_VER="$INFINIA_VERSION"

    # Ensure wget and envsubst are installed (add to initial setup if not)
    # sudo apt-get update && sudo apt-get install -y wget gettext-base
    wget $BASE_PKG_URL/releases/rmd_template.json -O /tmp/rmd_template.json
    envsubst < /tmp/rmd_template.json > /tmp/rmd.json

    # Get the primary private IP address
    IP_ADDRESS=$(fetch_aws_metadata "local-ipv4")
    # Or for a specific network interface:
    # IP_ADDRESS=$(fetch_aws_metadata "network/interfaces/macs/YOUR_MAC_ADDRESS/local-ipv4s")

    sudo redsetup -realm-entry \
        -realm-entry-secret "$REALM_ENTRY_SECRET" \
        --admin-password "$ADMIN_PASSWORD" \
        -ctrl-plane-ip "$IP_ADDRESS" \
        -release-metadata-file /tmp/rmd.json \
        -skip-reboot # Assuming -skip-reboot means it won't reboot immediately, but the script will handle the final reboot.

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
