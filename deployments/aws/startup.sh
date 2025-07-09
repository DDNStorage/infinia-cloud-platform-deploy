#!/bin/bash

# Export variables passed from Terraform
export INFINIA_VERSION="${infinia_version}"
export REALM_ENTRY_HOST="${realm_entry_host}"
export REALM_ENTRY_SECRET="${realm_entry_secret}"
export REALM_ENTRY="${realm_entry}" # This seems to be intentionally empty based on your locals
export ADMIN_PASSWORD="${admin_password}" # This seems to be intentionally empty based on your locals
export INFINIA_INSTANCE_COUNT="${infinia_instance_count}"
export INFINIA_LICENSE="${infinia_license}"
export BASE_PKG_URL="${base_pkg_url}"
export RELEASE_TYPE="${release_type}" # This seems to be intentionally empty based on your locals
export REL_DIST_PATH="${rel_dist_path}"

export TARGET_ARCH=$(dpkg --print-architecture)
export REL_PKG_URL="${BASE_PKG_URL}/releases${RELEASE_TYPE}/${REL_DIST_PATH}" # Using interpolated RELEASE_TYPE

# Set RED_VER based on INFINIA_VERSION
export RED_VER="${INFINIA_VERSION}"

# Update apt package lists before installing
apt-get update -y

apt-get install -y lldpd

if systemctl list-units --type=service | grep -q lldpd.service; then
  systemctl enable lldpd && systemctl restart lldpd
else
  echo 'lldpd.service not found, skipping...'
fi

wget "${BASE_PKG_URL}/releases${RELEASE_TYPE}/${REL_DIST_PATH}/redsetup_${INFINIA_VERSION}_$(dpkg --print-architecture)${RELEASE_TYPE}.deb?cache-time=$(date +%s)" -O /tmp/redsetup.deb
apt install -y /tmp/redsetup.deb

wget "${BASE_PKG_URL}/releases/rmd_template.json" -O /tmp/rmd_template.json
# Ensure envsubst is installed if not present
apt-get install -y gettext-base # envsubst is part of gettext-base package
envsubst < /tmp/rmd_template.json > /tmp/rmd.json

redsetup -realm-entry "${REALM_ENTRY}" -realm-entry-secret "${REALM_ENTRY_SECRET}" --admin-password "${ADMIN_PASSWORD}" -ctrl-plane-ip $(hostname --ip-address) -release-metadata-file /tmp/rmd.json -skip-reboot -skip-hardware-check
redsetup -reset

rm -rf /var/cache/apt /tmp/*
apt-get autoremove -y && apt-get clean
rm -rf /var/lib/apt/lists/*
journalctl --rotate && journalctl --vacuum-time=1s
rm -rf /var/log/* /tmp/* /var/tmp/*
