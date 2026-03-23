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

# Create reduser and setup SSH (reads from GCS, no write needed)
create_reduser() {
    log_info "Creating reduser account"
    
    if ! id "reduser" &>/dev/null; then
        useradd -m -s /bin/bash reduser
        usermod -aG google-sudoers reduser
        echo "reduser ALL=(ALL) NOPASSWD:ALL" | tee /etc/sudoers.d/90-reduser > /dev/null
        chmod 440 /etc/sudoers.d/90-reduser
        log_info "reduser created successfully"
    fi
    
    # Setup SSH keys (READ-ONLY from GCS)
    mkdir -p /home/reduser/.ssh
    chmod 700 /home/reduser/.ssh
    
    # Download shared keys from GCS (READ access only)
    gsutil cp gs://red-images/red-on-gcp-mp/reduser_id_rsa.pub /home/reduser/.ssh/id_rsa.pub || error_exit "Failed to copy reduser public key"
    gsutil cp gs://red-images/red-on-gcp-mp/reduser_id_rsa /home/reduser/.ssh/id_rsa || error_exit "Failed to copy reduser private key"
    
    # Setup authorized_keys
    cat /home/reduser/.ssh/id_rsa.pub > /home/reduser/.ssh/authorized_keys
    
    # Set permissions
    chmod 600 /home/reduser/.ssh/id_rsa
    chmod 644 /home/reduser/.ssh/id_rsa.pub
    chmod 600 /home/reduser/.ssh/authorized_keys
    chown -R reduser:reduser /home/reduser/.ssh
    
    # SSH config
    cat > /home/reduser/.ssh/config <<'EOF'
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
    IdentityFile /home/reduser/.ssh/id_rsa
EOF
    chmod 600 /home/reduser/.ssh/config
    chown reduser:reduser /home/reduser/.ssh/config
    
    log_info "reduser SSH configured successfully"
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

create_reduser

# Configure SSH agent forwarding for ALL users (gyadav, fzhu, etc.)
log_info "Configuring SSH agent forwarding for all users"

# Create SSH config template for all users
cat > /etc/skel/.ssh/config <<'EOF'
Host *
    ForwardAgent yes
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
EOF

# Apply to existing users
for user_home in /home/*; do
    if [ -d "$user_home" ]; then
        username=$(basename "$user_home")
        mkdir -p "$user_home/.ssh"
        cp /etc/skel/.ssh/config "$user_home/.ssh/config" 2>/dev/null || true
        chmod 600 "$user_home/.ssh/config" 2>/dev/null || true
        chown -R "$username:$username" "$user_home/.ssh" 2>/dev/null || true
    fi
done

cat > /etc/sudoers.d/90-ssh-agent-forwarding <<'EOF'
# Preserve SSH agent socket for SSH forwarding
Defaults env_keep += "SSH_AUTH_SOCK"
EOF
chmod 440 /etc/sudoers.d/90-ssh-agent-forwarding
log_info "SSH agent forwarding configured"

# Get metadata
PD_DISK_COUNT=$(fetch_metadata "${ATTRIBUTES_METADATA_URL}/pd_disk_count")

if [ -n "$PD_DISK_COUNT" ] && [ "$PD_DISK_COUNT" -gt 0 ]; then
    log_info "Validating persistent disk count..."
    validate_disk_count "$PD_DISK_COUNT"
fi

# Create marker file
log_info "Creating marker file"
mkdir -p /var/lib/infinia
touch /var/lib/infinia/infra-ready
log_info "Marker file created"

# Clear and reset machine-id
log_info "Resetting machine-id before running redsetup..."
rm -f /etc/machine-id && systemd-machine-id-setup
log_info "Machine-id reset completed"

log_info "Infrastructure-only setup completed successfully"


