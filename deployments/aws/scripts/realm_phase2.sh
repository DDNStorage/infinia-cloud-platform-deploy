#!/usr/bin/env bash
# scripts/realm_phase2.sh
# Run the post-boot realm steps via SSM on the realm node, without sed substitution.

set -euo pipefail

# -----------------------
# Defaults / CLI parsing
# -----------------------
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
INSTANCE_ID=""
DEPLOYMENT_TAG=""       # optional: filter by Deployment tag
WANT_NODES="${WANT:-}"  # may be provided via env; else set with --want
ADMIN_PW="${ADMIN_PW:-}"
LICENSE_KEY="${LICENSE_KEY:-}"

usage() {
  cat <<USAGE
Usage: $0 [--region REGION] [--instance-id i-xxxxxxxxx] [--deployment NAME] \\
          --want N --admin ADMIN_PASSWORD --license LICENSE_KEY

Examples:
  export AWS_REGION=us-east-1
  $0 --deployment my-deploy --want 7 --admin 'PA-ssW00r^d' --license '1DE9-....'
  $0 --instance-id i-0abc123... --want 7 --admin '...' --license '...'

Notes:
- If --instance-id is omitted, the script finds the realm by tags:
    Role=realm (and Deployment=<NAME> if --deployment is given)
- Requires AWS CLI, jq and SSM permissions locally.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)       REGION="$2"; shift 2;;
    --instance-id)  INSTANCE_ID="$2"; shift 2;;
    --deployment)   DEPLOYMENT_TAG="$2"; shift 2;;
    --want)         WANT_NODES="$2"; shift 2;;
    --admin)        ADMIN_PW="$2"; shift 2;;
    --license)      LICENSE_KEY="$2"; shift 2;;
    -h|--help)      usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

if [[ -z "$WANT_NODES" || -z "$ADMIN_PW" || -z "$LICENSE_KEY" ]]; then
  echo "[tf] ERROR: --want, --admin and --license are required." >&2
  usage
  exit 2
fi

echo "[tf] realm_phase2: REGION=$REGION WANT=$WANT_NODES DEPLOYMENT=$DEPLOYMENT_TAG INSTANCE_ID=${INSTANCE_ID:-<auto>}"

# -----------------------
# Helpers
# -----------------------
aws_ec2_state() {
  aws --region "$REGION" ec2 describe-instances \
    --instance-ids "$1" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text 2>/dev/null || echo "unknown"
}

aws_find_realm_instance() {
  local filters="Name=tag:Role,Values=realm Name=instance-state-name,Values=pending,running,stopping,stopped"
  if [[ -n "$DEPLOYMENT_TAG" ]]; then
    filters="$filters Name=tag:Deployment,Values=$DEPLOYMENT_TAG"
  fi

  aws --region "$REGION" ec2 describe-instances \
    --filters $filters \
    --query 'Reservations[].Instances[].{Id:InstanceId,Launch:LaunchTime}' \
    --output json \
  | jq -r 'sort_by(.Launch)|reverse|.[0].Id // empty'
}

aws_wait_ec2_running() {
  local id="$1"
  echo "[tf] waiting for EC2 to be running…"
  for _ in $(seq 1 180); do
    local st
    st="$(aws_ec2_state "$id")"
    echo "[tf] EC2 state: $st"
    [[ "$st" == "running" ]] && return 0
    sleep 5
  done
  return 1
}

aws_ssm_ping_status() {
  aws --region "$REGION" ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=$1" \
    --query 'InstanceInformationList[0].PingStatus' \
    --output text 2>/dev/null || echo "None"
}

aws_wait_ssm_online() {
  local id="$1"
  echo "[tf] waiting for SSM Online…"
  for _ in $(seq 1 180); do
    local ping
    ping="$(aws_ssm_ping_status "$id")"
    echo "[tf] SSM PingStatus: $ping"
    [[ "$ping" == "Online" ]] && return 0
    sleep 5
  done
  return 1
}

b64_inline() {
  if base64 -w0 /dev/null >/dev/null 2>&1; then
    base64 -w0
  else
    base64 | tr -d '\n'
  fi
}

# -----------------------
# Instance resolution
# -----------------------
if [[ -z "$INSTANCE_ID" ]]; then
  INSTANCE_ID="$(aws_find_realm_instance)"
  if [[ -z "$INSTANCE_ID" ]]; then
    echo "[tf] ERROR: No realm instance found by tags (Role=realm${DEPLOYMENT_TAG:+, Deployment=$DEPLOYMENT_TAG})." >&2
    exit 3
  fi
fi
echo "[tf] Using INSTANCE_ID=$INSTANCE_ID"

# -----------------------
# Wait for EC2 + SSM
# -----------------------
aws_wait_ec2_running "$INSTANCE_ID" || { echo "[tf] ERROR: instance never reached 'running'"; exit 4; }
aws_wait_ssm_online  "$INSTANCE_ID" || { echo "[tf] ERROR: SSM never reached 'Online'"; exit 5; }

# -----------------------
# Remote script (reads env vars ADMIN_PW, LICENSE_KEY, WANT)
# -----------------------
TMPDIR="$(mktemp -d)"
SCRIPT="$TMPDIR/phase2.sh"

cat >"$SCRIPT" <<'EOSH'
#!/usr/bin/env bash
set -euo pipefail
LOG=/var/log/red-phase2-tf.log
exec > >(tee -a "$LOG") 2>&1

: "${ADMIN_PW:?missing ADMIN_PW}"
: "${LICENSE_KEY:?missing LICENSE_KEY}"
: "${WANT:?missing WANT}"

echo "[phase2] start"

# Bounded wait for inventory to reach expected count (or timeout and proceed)
TRIES=0
while :; do
  redcli realm config generate || true
  nodes="$(redcli inventory show 2>/dev/null | awk '/^[[:space:]]*Nodes:/ {print $2; exit}')"
  [[ -z "$nodes" ]] && nodes=0
  echo "[phase2] Nodes=$nodes want=$WANT try=$TRIES"
  [[ "$nodes" -ge "$WANT" ]] && break
  TRIES=$((TRIES+1))
  [[ "$TRIES" -ge 120 ]] && break   # ~20 minutes at 10s
  sleep 10
done

# Ensure config exists then update (retry a bit inline)
[[ -s realm_config.yaml ]] || redcli realm config generate || true
tries=0
until redcli realm config update -f realm_config.yaml; do
  tries=$((tries+1))
  [[ "$tries" -ge 8 ]] && { echo "[phase2] realm config update failed after retries"; break; }
  echo "[phase2] realm config update retry $tries/8"
  sleep 8
done

# Login (API may come up right after config)
TRIES=0
until redcli user login realm_admin -p "$ADMIN_PW"; do
  TRIES=$((TRIES+1))
  [[ "$TRIES" -ge 18 ]] && { echo "[phase2] FATAL: login failed"; exit 1; }
  echo "[phase2] login retry $TRIES/18"
  sleep 10
done

# License (idempotent)
redcli license show >/dev/null 2>&1 || redcli license install -a "$LICENSE_KEY" -y
redcli license show || true

# Cluster create (idempotent; accept already-exists/running)
OUT="$(redcli cluster create c1 -S=false -z -f 2>&1)" || true
echo "$OUT"
echo "$OUT" | grep -qiE 'already exists|created|is running' || true

# Final status (non-fatal)
redcli cluster show || true
echo "[phase2] done"
EOSH

B64="$(b64_inline < "$SCRIPT")"

# -----------------------
# SSM parameters: write script, chmod, then run with env vars
# -----------------------
PARAMS="$TMPDIR/params.json"
cat >"$PARAMS"<<JSON
{
  "commands": [
    "echo $B64 | base64 -d > /tmp/phase2.sh",
    "chmod +x /tmp/phase2.sh",
    "ADMIN_PW='${ADMIN_PW}' LICENSE_KEY='${LICENSE_KEY}' WANT='${WANT_NODES}' bash /tmp/phase2.sh"
  ]
}
JSON

# -----------------------
# Send command & poll
# -----------------------
CMD_ID="$(
  aws --region "$REGION" ssm send-command \
    --document-name "AWS-RunShellScript" \
    --instance-ids "$INSTANCE_ID" \
    --parameters file://"$PARAMS" \
    --timeout-seconds 2700 \
    --query 'Command.CommandId' \
    --output text
)"
echo "[tf] SSM CommandId=$CMD_ID"
echo "$INSTANCE_ID" > ./.phase2_instance_id
echo "$CMD_ID"      > ./.phase2_cmdid

for _ in $(seq 1 540); do
  STATUS="$(aws --region "$REGION" ssm get-command-invocation \
    --command-id "$CMD_ID" \
    --instance-id "$INSTANCE_ID" \
    --query 'Status' --output text 2>/dev/null || echo 'Pending')"
  echo "[tf] SSM status: $STATUS"
  case "$STATUS" in
    Success)
      echo "[tf] Phase-2 completed successfully."
      exit 0
      ;;
    Failed|Cancelled|TimedOut)
      echo "----- Remote output -----"
      aws --region "$REGION" ssm get-command-invocation \
        --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" --output text || true
      exit 1
      ;;
  esac
  sleep 5
done

echo "[tf] Timed out waiting for Phase-2 SSM command."
exit 1
