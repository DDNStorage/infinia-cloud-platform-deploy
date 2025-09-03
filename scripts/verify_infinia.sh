#!/usr/bin/env bash
# scripts/verify_infinia.sh
set -euo pipefail

# ===== Inputs (environment) =====
AWS_REGION="${AWS_REGION:-${REGION:-${AWS_DEFAULT_REGION:-}}}"
TERRAFORM_DIR="${TERRAFORM_DIR:-deployments/aws}"
REALM_ADMIN_PASSWORD="${REALM_ADMIN_PASSWORD:-${INFINIA_ADMIN_PASSWORD:-}}"
AMI_ID="${AMI_ID:-}"   # optional, strengthens AWS fallback filters

# ===== Helpers =====
need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing dependency: $1" >&2; exit 1; }; }
b64_no_wrap() {
  if base64 --help 2>&1 | grep -q -- '-w'; then base64 -w0; else base64; fi
}

# ===== Preflight =====
for bin in aws jq terraform awk sed; do need "$bin"; done
[[ -n "$AWS_REGION" ]] || { echo "ERROR: AWS_REGION not set" >&2; exit 1; }
[[ -n "$REALM_ADMIN_PASSWORD" ]] || { echo "ERROR: REALM_ADMIN_PASSWORD not set" >&2; exit 1; }
aws sts get-caller-identity >/dev/null || { echo "ERROR: AWS credentials not usable" >&2; exit 1; }

# ===== Discover instance IDs from Terraform state (robust) =====
pushd "$TERRAFORM_DIR" >/dev/null

# Match both with/without module prefix and with/without [index]
REALM_ADDR="$(terraform state list | awk '/(^|.*\.)aws_instance\.infinia_realm(\[[0-9]+\])?$/ {print; exit}')"
mapfile -t NONREALM_ADDRS < <(terraform state list | awk '/(^|.*\.)aws_instance\.infinia_none_realm(\[[0-9]+\])?$/ {print}')

REALM_ID=""
AMI_FROM_STATE=""

if [[ -n "${REALM_ADDR:-}" ]]; then
  REALM_ID="$(terraform state show -no-color "$REALM_ADDR" \
    | awk -F ' = ' '/^id = /{gsub(/"/,"",$2); print $2; exit}')"
  AMI_FROM_STATE="$(terraform state show -no-color "$REALM_ADDR" \
    | awk -F ' = ' '/^ami = /{gsub(/"/,"",$2); print $2; exit}')"
fi

NONREALM_IDS=""
if [[ ${#NONREALM_ADDRS[@]} -gt 0 ]]; then
  for RES in "${NONREALM_ADDRS[@]}"; do
    _id="$(terraform state show -no-color "$RES" \
      | awk -F ' = ' '/^id = /{gsub(/"/,"",$2); print $2; exit}')"
    [[ -n "$_id" ]] && NONREALM_IDS+="${_id} "
  done
  NONREALM_IDS="$(echo "$NONREALM_IDS" | xargs || true)"
fi

popd >/dev/null

# ===== AWS fallback(s) if TF state didn't give us IDs =====
AMI_FILTER="${AMI_ID:-$AMI_FROM_STATE}"

if [[ -z "$REALM_ID" ]]; then
  echo "WARN: Realm ID not found in TF state. Falling back to AWS describe-instances..."
  # Filter by Role=realm; optionally constrain by AMI if available
  if [[ -n "$AMI_FILTER" ]]; then
    REALM_ID="$(aws ec2 describe-instances --region "$AWS_REGION" \
      --filters Name=instance-state-name,Values=running,pending \
                Name=tag:Role,Values=realm \
                Name=image-id,Values="$AMI_FILTER" \
      --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null | awk '{print $1}')"
  else
    REALM_ID="$(aws ec2 describe-instances --region "$AWS_REGION" \
      --filters Name=instance-state-name,Values=running,pending \
                Name=tag:Role,Values=realm \
      --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null | awk '{print $1}')"
  fi
fi

if [[ -z "$NONREALM_IDS" ]]; then
  echo "INFO: Non-realm IDs not found in TF state. Falling back to AWS describe-instances..."
  if [[ -n "$AMI_FILTER" ]]; then
    NONREALM_IDS="$(aws ec2 describe-instances --region "$AWS_REGION" \
      --filters Name=instance-state-name,Values=running,pending \
                Name=tag:Role,Values=nonrealm \
                Name=image-id,Values="$AMI_FILTER" \
      --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null | xargs || true)"
  else
    NONREALM_IDS="$(aws ec2 describe-instances --region "$AWS_REGION" \
      --filters Name=instance-state-name,Values=running,pending \
                Name=tag:Role,Values=nonrealm \
      --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null | xargs || true)"
  fi
fi

IDS="$(echo "$REALM_ID $NONREALM_IDS" | xargs)"
[[ -n "$REALM_ID" ]] || { echo "ERROR: could not find realm instance id (TF state or AWS fallback)" >&2; exit 1; }
[[ -n "$IDS" ]] || { echo "ERROR: no instances found (realm + nonrealm)" >&2; exit 1; }

EXPECTED=$(( $(wc -w <<<"${NONREALM_IDS:-}" | xargs) + 1 ))
echo "Realm:   $REALM_ID"
echo "Clients: ${NONREALM_IDS:-<none>}"
echo "Expected node count: $EXPECTED"

# ===== Wait for EC2 checks and SSM Online =====
deadline=$((SECONDS + 1800)) # 30 min
NUM=$(wc -w <<<"$IDS" | xargs)
while :; do
  OK=$(aws ec2 describe-instance-status --region "$AWS_REGION" \
        --include-all-instances --instance-ids $IDS \
        --query "length(InstanceStatuses[?InstanceStatus.Status=='ok' && SystemStatus.Status=='ok'])" \
        --output text)
  echo "EC2 checks OK: $OK / $NUM"
  [[ "$OK" == "$NUM" ]] && break
  (( SECONDS > deadline )) && { echo "ERROR: timeout waiting for EC2 checks" >&2; exit 1; }
  sleep 15
done

for ID in $IDS; do
  echo "Waiting SSM Online: $ID"
  for i in {1..80}; do
    STATUS=$(aws ssm describe-instance-information --region "$AWS_REGION" \
      --query "InstanceInformationList[?InstanceId=='${ID}'].PingStatus" --output text 2>/dev/null || true)
    [[ "$STATUS" == *Online* ]] && { echo "SSM Online for $ID"; break; }
    sleep 5
    [[ $i -eq 80 ]] && { echo "ERROR: timeout waiting SSM for $ID" >&2; exit 1; }
  done
done

# ===== Run redcli on the realm via SSM =====
PASS_B64="$(printf '%s' "$REALM_ADMIN_PASSWORD" | b64_no_wrap)"

run_ssm() {
  local iid="$1" cmd_id status

  read -r -d '' REMOTE <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
PASS=$(printf '%s' '__PASS_B64__' | base64 -d)
redcli user login realm_admin -p "$PASS"
JSON="$( (redcli cluster show -o json || redcli cluster show --json) 2>/dev/null || true )"
if [ -z "$JSON" ]; then
  JSON="$( (redcli inventory show --json || redcli inventory show -o json) 2>/dev/null || true )"
fi
printf "__JSON_START__\n%s\n__JSON_END__\n" "$JSON"
EOS

  local SCRIPT=${REMOTE//'__PASS_B64__'/$PASS_B64}
  local CMD_JSON
  CMD_JSON=$(printf '%s' "$SCRIPT" \
    | jq -Rs '["bash -lc \"" + (gsub("\\\\";"\\\\")|gsub("\"";"\\\"")|gsub("\n";"\\n")) + "\""]')

  cmd_id=$(aws ssm send-command \
    --region "$AWS_REGION" \
    --instance-ids "$iid" \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=${CMD_JSON}" \
    --query 'Command.CommandId' --output text)

  while :; do
    status=$(aws ssm get-command-invocation \
      --region "$AWS_REGION" \
      --command-id "$cmd_id" \
      --instance-id "$iid" \
      --query 'Status' --output text 2>/dev/null || echo Unknown)
    [[ "$status" =~ ^(Pending|InProgress|Delayed)$ ]] || break
    sleep 3
  done

  aws ssm get-command-invocation \
    --region "$AWS_REGION" \
    --command-id "$cmd_id" \
    --instance-id "$iid" \
    --output json
}

RESP="$(run_ssm "$REALM_ID")"
STATUS="$(echo "$RESP" | jq -r '.Status')"
STDOUT="$(echo "$RESP" | jq -r '.StandardOutputContent')"
STDERR="$(echo "$RESP" | jq -r '.StandardErrorContent')"

echo "SSM status: $STATUS"
if [[ "$STATUS" != "Success" ]]; then
  echo "ERROR: SSM command failed"
  echo "$STDERR"
  exit 1
fi

JSON="$(awk '/__JSON_START__/{f=1;next}/__JSON_END__/{f=0}f' <<< "$STDOUT")"
[[ -n "$JSON" && "$JSON" != "null" ]] || { echo "ERROR: no JSON from redcli" >&2; exit 1; }

STATE="$(jq -r '.cluster_state // .state // "unknown"' <<< "$JSON")"
COUNT="$(jq '(.instances|length) // (.nodes|length) // 0' <<< "$JSON")"
EVICTED="$(jq '([.cats[]? | select(.evicted==true)] | length) // 0' <<< "$JSON")"
NAMES="$(jq -r '(.instances // .nodes // []) | map(.name // .id // .instance_id // .hostname // .node // .Name) | join(", ")' <<< "$JSON")"

# ===== Summary =====
{
  echo "### Infinia functional verification"
  echo
  echo "- Realm instance: \`$REALM_ID\`"
  echo "- Expected nodes (TF/AWS): \`$EXPECTED\`"
  echo "- redcli state: \`$STATE\`"
  echo "- redcli nodes: \`$COUNT\`"
  echo "- Evicted CATs: \`$EVICTED\`"
  [[ -n "$NAMES" ]] && echo "- Nodes: $NAMES"
  echo
  echo "<details><summary>Raw redcli JSON</summary>"
  echo
  echo '```json'
  echo "$JSON"
  echo '```'
  echo "</details>"
} | tee /dev/fd/3 3>/dev/null >> "${GITHUB_STEP_SUMMARY:-/dev/null}" || true

# ===== Health gates =====
[[ "$STATE" == "running" ]] || { echo "ERROR: cluster state is '$STATE' (want 'running')" >&2; exit 1; }
[[ "${EVICTED:-0}" -eq 0 ]] || { echo "ERROR: evicted CATs: $EVICTED" >&2; exit 1; }
[[ "${COUNT:-0}" -eq "$EXPECTED" ]] || { echo "ERROR: node count mismatch: expected $EXPECTED, got ${COUNT:-0}" >&2; exit 1; }

echo "Cluster verification OK ✅"
