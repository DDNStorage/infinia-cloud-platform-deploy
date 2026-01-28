locals {
  instance_count = var.num_infinia_instances + 1
  admin_password = var.admin_password
  realm_license  = var.realm_license

  # VPC and subnet selection logic
  vpc_id = var.create_vpc ? aws_vpc.main[0].id : var.vpc_id

  # When creating VPC: use only private subnets for instances (skip first subnet which is public)
  # When using existing VPC: use all provided subnets
  subnet_ids = var.create_vpc ? slice(aws_subnet.main[*].id, 1, length(aws_subnet.main[*].id)) : var.subnet_ids

  security_group_id = var.create_vpc ? aws_security_group.default[0].id : var.security_group_id
}

locals {
  user_startup_script_realm = <<EOT
#!/bin/bash
export INFINIA_VERSION="${var.infinia_version}"
export BASE_PKG_URL="https://storage.googleapis.com/ddn-redsetup-public"
export RELEASE_TYPE=""
export REL_DIST_PATH="ubuntu/24.04"
export TARGET_ARCH=$(dpkg --print-architecture)
export REL_PKG_URL="${var.base_pkg_url}/releases${var.release_type}/${var.rel_dist_path}"
LOG_COMPLETE="/etc/red/phase_one_compelete"
LOG_FILE="/tmp/log"
NODE_COUNT="${local.instance_count}"
rm /etc/machine-id && sudo systemd-machine-id-setup

log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Disk validation function with retry logic
validate_attached_disks() {
    local expected_ebs_count=${var.use_ebs_volumes ? var.ebs_volumes_per_vm : 0}
    local max_retries=6
    local retry_count=0
    local base_delay=15

    log_info "Starting disk validation - expected EBS volumes: $expected_ebs_count"

    while [ $retry_count -lt $max_retries ]; do
        retry_count=$((retry_count + 1))
        log_info "Disk validation attempt $retry_count/6"

        # Count nvme disks and subtract 1 for root volume
        local total_disks=$(lsblk -dn -o NAME | grep -c "^nvme")
        local actual_ebs_count=$((total_disks - 1))

        log_info "Found $actual_ebs_count EBS volumes (total disks: $total_disks), expected $expected_ebs_count"

        if [ "$actual_ebs_count" -eq "$expected_ebs_count" ]; then
            log_info "✓ Disk validation successful: All expected EBS volumes are attached"
            return 0
        fi

        # Calculate delay with exponential backoff
        local delay=$((base_delay * (2 ** (retry_count - 1))))
        [ $delay -gt 120 ] && delay=120  # Cap at 2 minutes

        log_info "⚠ Disk validation failed: Expected $expected_ebs_count EBS volumes, found $actual_ebs_count"
        log_info "Retrying in $delay seconds... (attempt $retry_count/$max_retries)"

        # Output detailed disk information for debugging
        log_info "Current disk layout:"
        lsblk | tee -a "$LOG_FILE"

        sleep $delay
    done

    # Final failure - output comprehensive error information
    log_info "❌ FATAL ERROR: Disk validation failed after $max_retries attempts"
    log_info "Expected EBS volumes: $expected_ebs_count"
    log_info "Found EBS volumes: $(($(lsblk -dn -o NAME | grep -c "^nvme") - 1))"
    log_info "Complete disk information:"
    lsblk -a | tee -a "$LOG_FILE"

    # GitHub Actions friendly output
    echo "::error title=Disk Validation Failed::Expected $expected_ebs_count EBS volumes but found $(($(lsblk -dn -o NAME | grep -c "^nvme") - 1)) EBS volumes"

    # Exit to prevent redsetup from continuing
    exit 1
}

_check_inventory(){
     while true; do
        val1=$(redcli inventory show | grep Nodes | awk '{print $2}')
        val2=$(echo $NODE_COUNT )
        if [ "$val1" = "$val2" ]; then
            break
        else
            log_info "Waiting for nodes to join.."
            sleep 5
        fi
    done
}

# Validate attached disks before proceeding with redsetup
validate_attached_disks

if [ ! -f $LOG_COMPLETE ] ; then
   wget "${var.base_pkg_url}/releases${var.release_type}/${var.rel_dist_path}/redsetup_${var.infinia_version}_$(dpkg --print-architecture)${var.release_type}.deb?cache-time=$(date +%s)" -O /tmp/redsetup.deb
   apt install -y /tmp/redsetup.deb | tee  -a $LOG_FILE
   rm  -rf "/etc/red/deploy/config.lock" && redsetup -reset || log_info "Error running redsetup reset"
   log_info "Wait for self inventory " && sleep 60
   redsetup -realm-entry -realm-entry-secret ${local.admin_password} --admin-password ${local.admin_password} -ctrl-plane-ip $(hostname --ip-address)  -skip-reboot  | tee -a $LOG_FILE
   log_info "reboot"
   touch $LOG_COMPLETE
   reboot -f 
else 
  cd /tmp 
    redcli user login realm_admin -p ${local.admin_password}   || log_info "Error: redcli login failed"
    redcli inventory show > inventory.log 
    grep -qi 'cpu' inventory.log || log_info  "Still waiting for self inventory" && sleep 60
    
    # First inventory init and compare 
    redcli realm config generate && _check_inventory || log_info "Error: Failed to generate config"
    
    # Regenerate when none realm joined the cluster
    redcli realm config generate  || log_info "Error Generating config file"
    redcli realm config update -f realm_config.yaml || log_info "Error updating realm"
    redcli license install -a ${local.realm_license} -y | tee -a $LOG_FILE
    redcli cluster create c1 -S=false -z  -f   |  tee -a "$LOG_FILE" || log_info "Error: failed to create cluster" 
    systemctl disable  cloudinit-rerun.service  --now
    rm -rf /var/lib/apt/lists/*
    journalctl --rotate && journalctl --vacuum-time=1s
    systemctl disable  cloudinit-rerun.service  --now
  fi
EOT
}

locals {
  user_startup_script_none_realm = <<EOT
#!/bin/bash
export INFINIA_VERSION="${var.infinia_version}"
export BASE_PKG_URL="https://storage.googleapis.com/ddn-redsetup-public"
export RELEASE_TYPE=""
export REL_DIST_PATH="ubuntu/24.04"
export TARGET_ARCH=$(dpkg --print-architecture)
export REL_PKG_URL="${var.base_pkg_url}/releases${var.release_type}/${var.rel_dist_path}"
LOG_COMPLETE="/etc/red/phase_one_compelete"
LOG_FILE="/tmp/log"
REALM_IP="${aws_instance.infinia_realm[0].private_ip}"
rm /etc/machine-id && sudo systemd-machine-id-setup
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Disk validation function with retry logic
validate_attached_disks() {
    local expected_ebs_count=${var.use_ebs_volumes ? var.ebs_volumes_per_vm : 0}
    local max_retries=6
    local retry_count=0
    local base_delay=15

    log_info "Starting disk validation - expected EBS volumes: $expected_ebs_count"

    while [ $retry_count -lt $max_retries ]; do
        retry_count=$((retry_count + 1))
        log_info "Disk validation attempt $retry_count/6"

        # Count nvme disks and subtract 1 for root volume
        local total_disks=$(lsblk -dn -o NAME | grep -c "^nvme")
        local actual_ebs_count=$((total_disks - 1))

        log_info "Found $actual_ebs_count EBS volumes (total disks: $total_disks), expected $expected_ebs_count"

        if [ "$actual_ebs_count" -eq "$expected_ebs_count" ]; then
            log_info "✓ Disk validation successful: All expected EBS volumes are attached"
            return 0
        fi

        # Calculate delay with exponential backoff
        local delay=$((base_delay * (2 ** (retry_count - 1))))
        [ $delay -gt 120 ] && delay=120  # Cap at 2 minutes

        log_info "⚠ Disk validation failed: Expected $expected_ebs_count EBS volumes, found $actual_ebs_count"
        log_info "Retrying in $delay seconds... (attempt $retry_count/$max_retries)"

        # Output detailed disk information for debugging
        log_info "Current disk layout:"
        lsblk | tee -a "$LOG_FILE"

        sleep $delay
    done

    # Final failure - output comprehensive error information
    log_info "❌ FATAL ERROR: Disk validation failed after $max_retries attempts"
    log_info "Expected EBS volumes: $expected_ebs_count"
    log_info "Found EBS volumes: $(($(lsblk -dn -o NAME | grep -c "^nvme") - 1))"
    log_info "Complete disk information:"
    lsblk -a | tee -a "$LOG_FILE"

    # GitHub Actions friendly output
    echo "::error title=Disk Validation Failed::Expected $expected_ebs_count EBS volumes but found $(($(lsblk -dn -o NAME | grep -c "^nvme") - 1)) EBS volumes"

    # Exit to prevent redsetup from continuing
    exit 1
}

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
            sleep 130
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


# Validate attached disks before proceeding with redsetup
validate_attached_disks

if [ ! -f $LOG_COMPLETE ] ; then
   wget "${var.base_pkg_url}/releases${var.release_type}/${var.rel_dist_path}/redsetup_${var.infinia_version}_$(dpkg --print-architecture)${var.release_type}.deb?cache-time=$(date +%s)" -O /tmp/redsetup.deb
   apt install -y /tmp/redsetup.deb
   rm  -rf "/etc/red/deploy/config.lock" && redsetup -reset  || log_info "Error running redsetup reset"
   retry_curl $REALM_IP
   redsetup --realm-entry-address $REALM_IP --realm-entry-secret ${local.admin_password} -skip-reboot -skip-hardware-check
   log_info "reboot"
   touch $LOG_COMPLETE
   reboot -f 
 else 
   rm -rf /var/lib/apt/lists/*
   journalctl --rotate && journalctl --vacuum-time=1s
   systemctl disable  cloudinit-rerun.service  --now
    
fi 
EOT
}

locals {
  base_url   = "https://storage.googleapis.com/ddn-redsetup-public/releases/ubuntu/24.04"
  qatest_url = "${local.base_url}/qatest"
  arch       = "amd64"

  user_startup_script_client = <<-EOF
    #!/usr/bin/env bash
    set -euo pipefail
    exec > /var/log/red-client-bootstrap.log 2>&1
    export DEBIAN_FRONTEND=noninteractive
    export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

    apt-get update -y
    apt-get install -y wget curl golang-go ca-certificates unzip
    install -d -m 0755 /usr/local/bin

    TMP=/tmp/red-client-install
    mkdir -p "$TMP"

    RED_VERSION="${var.infinia_version}"
    ARCH="${local.arch}"
    BASE_URL="${local.base_url}"
    QATEST_URL="${local.qatest_url}"

    # --- Install the .deb packages (with retry) ---
    for pkg in red-client-common red-client-tools redcli; do
      URL="$BASE_URL/$${pkg}_$${RED_VERSION}_$${ARCH}.deb"
      DEST="$TMP/$${pkg}_$${RED_VERSION}_$${ARCH}.deb"
      ok_pkg=0
      for i in $(seq 1 3); do
        if curl -fL "$URL" -o "$DEST"; then ok_pkg=1; break; fi
        echo "Retry $i fetching $URL ..." >&2
        sleep 5
      done
      [ "$ok_pkg" -eq 1 ] || { echo "Failed to download $pkg" >&2; exit 1; }
      apt-get install -y "$DEST" || apt-get -f install -y
    done

    # --- Install go-s3-tests (binary) (with retry) ---
    ok_gos3=0
    for i in $(seq 1 3); do
      if curl -fL "$QATEST_URL/go-s3-tests" -o /usr/local/bin/go-s3-tests; then
        chmod 0755 /usr/local/bin/go-s3-tests
        ok_gos3=1
        break
      fi
      echo "Retry $i fetching go-s3-tests ..." >&2
      sleep 5
    done
    [ "$ok_gos3" -eq 1 ] || { echo "Failed to install go-s3-tests" >&2; exit 1; }

    # --- Install AWS CLI v2 (arch-aware) ---
    AWS_TMP=/tmp/awscli
    mkdir -p "$AWS_TMP"
    case "$(dpkg --print-architecture)" in
      amd64) AWSCLI_ZIP="awscli-exe-linux-x86_64.zip" ;;
      arm64) AWSCLI_ZIP="awscli-exe-linux-aarch64.zip" ;;
      *)     AWSCLI_ZIP="awscli-exe-linux-x86_64.zip" ;;
    esac
    ok_aws=0
    for i in $(seq 1 3); do
      if curl -fL "https://awscli.amazonaws.com/$AWSCLI_ZIP" -o "$AWS_TMP/awscliv2.zip"; then
        ok_aws=1
        break
      fi
      echo "Retry $i fetching AWS CLI ..." >&2
      sleep 5
    done
    [ "$ok_aws" -eq 1 ] || { echo "Failed to download AWS CLI" >&2; exit 1; }
    unzip -o "$AWS_TMP/awscliv2.zip" -d "$AWS_TMP"
    "$AWS_TMP/aws/install" --update
    command -v aws >/dev/null || { echo "AWS CLI not found after install" >&2; exit 1; }

    # --- Final verification ---
    for b in redcli warp-ddn go-s3-tests aws; do
      if ! command -v "$b" >/dev/null; then
        echo "ERROR: $b not installed or not on PATH" >&2
        exit 1
      fi
    done

    rm -rf "$TMP" "$AWS_TMP"
  EOF
}
