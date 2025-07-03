#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[FATAL] bootstrap failed at line $LINENO"; exit 1' ERR
export PS4='+ $(date "+%Y-%m-%dT%H:%M:%S") ${BASH_SOURCE}:${LINENO} '

##############################################################################
# Argument parsing                                                           #
##############################################################################
VERSION=""
REALM_ENTRY=false
NON_REALM_ENTRY=false
REALM_IP=""
REALM_SECRET="PA-ssW00r^d"
ADMIN_PASSWORD="PA-ssW00r^d"
SKIP_REBOOT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--realm-entry)       REALM_ENTRY=true ;;
    -n|--non-realm-entry)   NON_REALM_ENTRY=true ;;
    -i|--ip)                REALM_IP="$2";          shift ;;
    -s|--realm-secret)      REALM_SECRET="$2";      shift ;;
    -p|--admin-password)    ADMIN_PASSWORD="$2";    shift ;;
    -v|--version)           VERSION="$2";           shift ;;
    --skip-reboot)          SKIP_REBOOT=true ;;
    *) echo "Unknown option $1"; exit 1 ;;
  esac; shift
done

[[ $REALM_ENTRY == true || $NON_REALM_ENTRY == true ]] || { echo "choose --realm-entry or --non-realm-entry"; exit 1; }
[[ $NON_REALM_ENTRY == false || -n "$REALM_IP"      ]] || { echo "--ip is mandatory for non‑realm nodes";  exit 1; }
[[ -n "$VERSION" ]] || { echo "--version is mandatory"; exit 1; }

##############################################################################
# OS packages & services                                                     #
##############################################################################
export DEBIAN_FRONTEND=noninteractive

# libssl1.1 is still required by redsetup runtime
echo "deb http://security.ubuntu.com/ubuntu focal-security main" \
     > /etc/apt/sources.list.d/libssl1.1-focal.list

apt-get update -qq
apt-get install -qq -y docker.io curl jq wget lldpd libssl1.1
systemctl enable --now docker lldpd

##############################################################################
# Download and install redsetup                                              #
##############################################################################
fetch() {
  local url="$1" dest="$2"
  curl -fSL "$url" -o "$dest" || { echo "[FATAL] cannot fetch $url"; exit 1; }
}

BASE_URL="https://storage.googleapis.com/ddn-redsetup-public/releases/ubuntu/24.04"
DEB="redsetup_${VERSION}_amd64.deb"
RMD="redsetup_${VERSION}.rmd.json"

echo "[INFO] downloading redsetup ${VERSION}"
fetch "${BASE_URL}/${DEB}" "/tmp/${DEB}"

if curl -fsIL "${BASE_URL}/${RMD}" >/dev/null; then
  echo "[INFO] downloading release metadata"
  fetch "${BASE_URL}/${RMD}" "/tmp/${RMD}"
  METADATA_OPT="-release-metadata /tmp/${RMD}"
else
  echo "[WARN] release metadata not found – continuing without it"
  METADATA_OPT=""
fi

apt-get install -qq -y "/tmp/${DEB}"

##############################################################################
# Clean previous installs                                                    #
##############################################################################
echo "[INFO] wiping previous RED state (if any)"
rm -f /etc/red/deploy/config.lock
redsetup --reset || true

##############################################################################
# Node configuration                                                         #
##############################################################################
PRIVATE_IP=$(hostname -I | awk '{print $1}')
export REDSETUP_LINK_SPEED_OVERRIDE=10000   # skip ENA speed check

if $REALM_ENTRY; then
  echo "[INFO] Configuring REALM node (${PRIVATE_IP})"
  redsetup -realm-entry \
           -realm-entry-secret "$REALM_SECRET" \
           -admin-password     "$ADMIN_PASSWORD" \
           -ctrl-plane-ip      "$PRIVATE_IP" \
           --skip-hardware-check \
           --disable-lldp \
           ${METADATA_OPT} \
           -verbose
else
  echo "[INFO] Configuring WORKER node (joining $REALM_IP)"
  redsetup -realm-entry-address "$REALM_IP" \
           -realm-entry-secret  "$REALM_SECRET" \
           --skip-hardware-check \
           ${METADATA_OPT} \
           -verbose
fi

[[ $SKIP_REBOOT == "false" ]] && reboot
echo "[INFO] done"
