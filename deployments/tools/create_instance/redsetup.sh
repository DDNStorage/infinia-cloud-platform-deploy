#!/bin/bash

# Usage function
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Automates RedSetup configuration and installation."
  echo ""
  echo "Options:"
  echo "  -s <secret>           Realm entry secret (required)"
  echo "  -p <admin_password>   Admin password (required)"
  echo "  -r <release_type>     Release type (default: \"\")"
  echo "  -d <dist_path>        Release distribution path (default: ubuntu/24.04)"
  echo "  -b <base_url>         Base package URL (default: https://storage.googleapis.com/ddn-redsetup-public)"
  echo "  -h                    Show this help message and exit"
  echo ""
  echo "Example:"
  echo "  $0 -s PA-ssW00r^d -p PA-ssW00r^d"
  echo ""
  exit 1
}

# Default values
BASE_PKG_URL="https://storage.googleapis.com/ddn-redsetup-public"
RELEASE_TYPE=""
REL_DIST_PATH="ubuntu/24.04"

# Parse CLI arguments
while getopts ":s:p:r:d:b:h" opt; do
  case $opt in
    s) REALM_SECRET="$OPTARG" ;;
    p) ADMIN_PASSWORD="$OPTARG" ;;
    r) RELEASE_TYPE="$OPTARG" ;;
    d) REL_DIST_PATH="$OPTARG" ;;
    b) BASE_PKG_URL="$OPTARG" ;;
    h) usage ;;
    \?) echo "Invalid option -$OPTARG" >&2; usage ;;
    :) echo "Option -$OPTARG requires an argument." >&2; usage ;;
  esac
done

# Validate required arguments
if [[ -z "$REALM_SECRET" || -z "$ADMIN_PASSWORD" ]]; then
  echo "Error: Both -s (secret) and -p (admin password) are required."
  usage
fi

# Derived values
TARGET_ARCH="$(dpkg --print-architecture)"
CTRL_PLANE_IP="$(hostname --ip-address)"
REL_PKG_URL="${BASE_PKG_URL}/releases${RELEASE_TYPE}/${REL_DIST_PATH}"

# Retrieve release version
RED_VER=$(wget -q -O - "${REL_PKG_URL}/RELEASE_VERSION_${TARGET_ARCH}.txt?cache-time=$(date +%s)")

if [[ -z "$RED_VER" ]]; then
  echo "Error: Failed to retrieve release version from $REL_PKG_URL"
  exit 1
fi

echo "Using RedSetup version: $RED_VER"

# Construct metadata file name
RELEASE_METADATA_FILE="rmd_${RED_VER}_${TARGET_ARCH}.json"

# Run the redsetup command
echo "Running redsetup with metadata file: $RELEASE_METADATA_FILE"

sudo redsetup \
  -realm-entry \
  -realm-entry-secret "$REALM_SECRET" \
  --admin-password "$ADMIN_PASSWORD" \
  -ctrl-plane-ip "$CTRL_PLANE_IP" \
  -release-metadata-file "$RELEASE_METADATA_FILE"

