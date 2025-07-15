#!/bin/bash

# Set error handling
set -e
trap 'echo "Error occurred at line $LINENO. Command: $BASH_COMMAND"' ERR

# Function to display usage
usage() {
    echo "Usage: $0 [-r|--realm-entry] [-n|--non-realm-entry] [-i|--ip IP_ADDRESS] [-v|--version VERSION] [-s|--realm-secret SECRET] [-p|--admin-password PASSWORD] [--skip-reboot]"
    echo "Options:"
    echo "  -r, --realm-entry        Configure as realm entry node"
    echo "  -n, --non-realm-entry    Configure as non-realm entry node"
    echo "  -i, --ip                 Realm entry IP address (mandatory with --non-realm-entry)"
    echo "  -v, --version            RedSetup version (mandatory)"
    echo "  -s, --realm-secret       Realm entry secret (optional, default: PA-ssW00r^d)"
    echo "  -p, --admin-password     Admin password (optional, default: PA-ssW00r^d)"
    echo "  --skip-reboot            Skip automatic reboot after installation (optional)"
    exit 1
}

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Parse arguments
REALM_ENTRY=false
NON_REALM_ENTRY=false
REALM_ENTRY_IP=""
RED_VER=""
REALM_SECRET="PA-ssW00r^d"
ADMIN_PASSWORD="PA-ssW00r^d"
SKIP_REBOOT=false

log "Parsing command line arguments..."
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--realm-entry)
            REALM_ENTRY=true
            log "Realm entry mode selected"
            shift
            ;;
        -n|--non-realm-entry)
            NON_REALM_ENTRY=true
            log "Non-realm entry mode selected"
            shift
            ;;
        -i|--ip)
            REALM_ENTRY_IP="$2"
            log "Realm entry IP set to: $REALM_ENTRY_IP"
            shift 2
            ;;
        -v|--version)
            RED_VER="$2"
            log "RedSetup version set to: $RED_VER"
            shift 2
            ;;
        -s|--realm-secret)
            REALM_SECRET="$2"
            log "Realm entry secret provided"
            shift 2
            ;;
        -p|--admin-password)
            ADMIN_PASSWORD="$2"
            log "Admin password provided"
            shift 2
            ;;
        --skip-reboot)
            SKIP_REBOOT=true
            log "Automatic reboot will be skipped"
            shift
            ;;
        *)
            log "Error: Invalid option $1"
            usage
            ;;
    esac
done

# Validation
log "Validating arguments..."
if [[ "$NON_REALM_ENTRY" == "true" && -z "$REALM_ENTRY_IP" ]]; then
    log "Error: --ip is mandatory when using --non-realm-entry"
    usage
fi

if [[ -z "$RED_VER" ]]; then
    log "Error: --version is mandatory"
    usage
fi

if [[ "$REALM_ENTRY" == "true" && "$NON_REALM_ENTRY" == "true" ]]; then
    log "Error: Cannot be both realm-entry and non-realm-entry"
    usage
fi

if [[ "$REALM_ENTRY" == "false" && "$NON_REALM_ENTRY" == "false" ]]; then
    log "Error: Must specify either --realm-entry or --non-realm-entry"
    usage
fi

# Setup environment
log "Setting up environment variables..."
export BASE_PKG_URL="https://storage.googleapis.com/ddn-redsetup-public"
export RELEASE_TYPE=""
export TARGET_ARCH="$(dpkg --print-architecture)"
export REL_DIST_PATH="ubuntu/24.04"
export REL_PKG_URL="${BASE_PKG_URL}/releases${RELEASE_TYPE}/${REL_DIST_PATH}"
export RED_VER

log "Environment configuration:"
log "- Architecture: $TARGET_ARCH"
log "- Distribution path: $REL_DIST_PATH"
log "- Package URL: $REL_PKG_URL"

# Download and install
log "Downloading redsetup package..."
if ! wget "$REL_PKG_URL/redsetup_${RED_VER}_${TARGET_ARCH}${RELEASE_TYPE}.deb?cache-time=$(date +%s)" \
    -O /tmp/redsetup.deb; then
    log "Error: Failed to download redsetup package"
    exit 1
fi

log "Installing redsetup package..."
if ! sudo apt install -y /tmp/redsetup.deb; then
    log "Error: Failed to install redsetup package"
    exit 1
fi

# Run redsetup
if [[ "$REALM_ENTRY" == "true" ]]; then
    log "Configuring realm entry node..."
    CMD="sudo redsetup --realm-entry-secret \"$REALM_SECRET\" --admin-password \"$ADMIN_PASSWORD\" --realm-entry --ctrl-plane-ip \"$(hostname -I | awk '{print $1}' | tr -d ' ')\""
    [[ "$SKIP_REBOOT" == "true" ]] && CMD="$CMD --skip-reboot"
    log "Executing: $CMD"
    eval $CMD || {
        log "Error: Failed to configure realm entry node"
        exit 1
    }
elif [[ "$NON_REALM_ENTRY" == "true" ]]; then
    log "Configuring non-realm entry node..."
    CMD="sudo redsetup --realm-entry-address \"$REALM_ENTRY_IP\" --realm-entry-secret \"$REALM_SECRET\""
    [[ "$SKIP_REBOOT" == "true" ]] && CMD="$CMD --skip-reboot"
    log "Executing: $CMD"
    eval $CMD || {
        log "Error: Failed to configure non-realm entry node"
        exit 1
    }
fi

log "Cleaning up temporary files..."
rm -f /tmp/redsetup.deb

log "Deployment completed successfully!"
