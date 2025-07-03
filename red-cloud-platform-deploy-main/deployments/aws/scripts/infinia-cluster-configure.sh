#!/bin/bash

# Set error handling
set -e
trap 'echo "Error occurred at line $LINENO. Command: $BASH_COMMAND"' ERR

# Function to display usage
usage() {
    echo "Usage: $0 [-h|--help] [-p PASSWORD] [-l LICENSE_KEY]"
    echo
    echo "This script configures an Infinia cluster after node deployment."
    echo
    echo "Options:"
    echo "  -h, --help        Display this help message"
    echo "  -p PASSWORD       Realm admin password"
    echo "  -l LICENSE_KEY    License key"
    echo
    echo "If password or license key are not provided via command line,"
    echo "the script will prompt for them interactively."
    echo
    echo "The script will:"
    echo "  1. Login as realm admin"
    echo "  2. Generate and update realm configuration"
    echo "  3. Install the provided license"
    echo "  4. Create and configure the cluster"
    echo "  5. Display cluster information"
    exit 1
}

# Function for logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to get license key
get_license() {
    read -p "Please enter your license key: " LICENSE_KEY
    if [[ -z "$LICENSE_KEY" ]]; then
        log "Error: License key cannot be empty"
        exit 1
    fi
}

# Function to get password
get_password() {
    read -s -p "Please enter realm admin password: " ADMIN_PASSWORD
    echo
    if [[ -z "$ADMIN_PASSWORD" ]]; then
        log "Error: Password cannot be empty"
        exit 1
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -p)
            shift
            ADMIN_PASSWORD="$1"
            ;;
        -l)
            shift
            LICENSE_KEY="$1"
            ;;
        *)
            log "Error: Invalid option $1"
            usage
            ;;
    esac
    shift
done

# Main execution
log "Starting cluster configuration..."

# Get credentials if not provided via command line
if [[ -z "$ADMIN_PASSWORD" ]]; then
    get_password
fi

if [[ -z "$LICENSE_KEY" ]]; then
    get_license
fi

log "Logging in as realm admin..."
if ! command -v redcli >/dev/null 2>&1; then
    log "Error: 'redcli' command not found. Please ensure RedCloud CLI tools are installed."
    exit 1
fi

if ! redcli user login realm_admin -p "$ADMIN_PASSWORD"; then
    log "Error: Failed to login as realm admin"
    exit 1
fi

log "Generating realm configuration..."
if ! redcli realm config generate; then
    log "Error: Failed to generate realm configuration"
    exit 1
fi

log "Updating realm configuration..."
if ! redcli realm config update -f realm_config.yaml; then
    log "Error: Failed to update realm configuration"
    exit 1
fi

log "Installing license..."
if ! redcli license install -a "$LICENSE_KEY" -y; then
    log "Error: Failed to install license"
    exit 1
fi

log "Creating cluster..."
if ! redcli cluster create c1 -S=false -z; then
    log "Error: Failed to create cluster"
    exit 1
fi

log "Displaying cluster information..."
if ! redcli cluster show; then
    log "Error: Failed to show cluster information"
    exit 1
fi

log "Cluster configuration completed successfully!"
