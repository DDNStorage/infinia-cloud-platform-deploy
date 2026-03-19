#!/bin/bash

set -e

LOG_FILE="/var/log/infra-only-deployment.log"
METADATA_URL="http://metadata.google.internal/computeMetadata/v1"
ATTRIBUTES_METADATA_URL="${METADATA_URL}/instance/attributes"
METADATA_FLAVOR_HEADER="Metadata-Flavor: Google"

# Logging function
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

error_exit() {
    log_info "ERROR: $1"
    exit 1
}

# Fetch metadata
fetch_metadata() {
    curl -s -H "${METADATA_FLAVOR_HEADER}" "$1" || echo ""
}

# Update package lists
log_info "Updating package lists"
apt update -y || error_exit "Failed to update package lists"

# Install basic dependencies
log_info "Installing basic dependencies"
apt install -y curl wget jq net-tools || error_exit "Failed to install basic dependencies"

# Setup SSH access between instances
setup_ssh_access() {
    log_info "Setting up SSH access"
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    
    if [ ! -f /root/.ssh/id_rsa ]; then
        ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
    fi
    
    cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    log_info "SSH access configured successfully"
}

# Validate disk count
validate_disk_count() {
    local expected_disk_count=$1
    local actual_disk_count=$(lsblk -d -n | grep -c "^sd" || true)
    
    log_info "Expected disk count: $expected_disk_count"
    log_info "Actual disk count: $actual_disk_count"
    
    if [ "$actual_disk_count" -lt "$expected_disk_count" ]; then
        error_exit "Disk count mismatch. Expected: $expected_disk_count, Found: $actual_disk_count"
    fi
    
    log_info "Disk validation successful"
}

# Main execution
log_info "Starting infrastructure-only setup"

setup_ssh_access

# Get metadata
PD_DISK_COUNT=$(fetch_metadata "${ATTRIBUTES_METADATA_URL}/pd_disk_count")

if [ -n "$PD_DISK_COUNT" ] && [ "$PD_DISK_COUNT" -gt 0 ]; then
    log_info "Validating persistent disk count..."
    validate_disk_count "$PD_DISK_COUNT"
fi

# Create marker file
mkdir -p /var/lib
touch /var/lib/infra-ready

log_info "Infrastructure-only setup completed successfully"
