#!/usr/bin/env bash
# scripts/verify_infinia.sh
set -euo pipefail

# ----- Inputs (env) -----
AWS_REGION="${AWS_REGION:-${REGION:-}}"
TERRAFORM_DIR="${TERRAFORM_DIR:-deployments/aws}"
REALM_ADMIN_PASSWORD="${REALM_ADMIN_PASSWORD:-${INFINIA_ADMIN_PASSWORD:-}}"

# ----- Helpers -----
need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing dependency: $1" >&2; exit 1; }; }
b64_no_wrap() {
  # GNU coreutils base64 (Ubuntu) supports -w0; fallback for others.
  if base64 --help 2>&1 | grep -q -- '-w'; then base64 -w0; else base64; fi
}

# ----- Preflight -----
for bin in aws jq terraform awk sed; do need "$bin"; done
[[ -n "$AWS_REGION" ]] || { echo "ERROR: AWS_REGION not set" >&2; exit 1; }
[[ -n "$REALM_ADMIN_PASSWORD" ]] || { echo "ERROR: REALM_ADMIN_PASSWORD not set" >&2; exit 1; }
aws sts get-caller-identity >/dev/null

# ----- Discover instance IDs from Terraform state -----
pushd "$TERRAFORM_DIR" >/dev/null
REALM_ID="$(terraform state show -no-color aws_instance.infinia_realm[0] | awk '/^id = /{print $3}')"
NONREALM_IDS="$(
  terraform state list | grep -E '^aws_instance\.infinia_none_realm' | \
  while read -r RES; do terraform state show -no-color "$RES" | awk '/^id = /{print $3}'; done | xargs
)"
popd >/dev/null

IDS="$(echo "$REALM_ID $NONREALM_IDS" | xargs)"
[[ -n "$REALM_ID" ]] || { echo "ERROR: could not find realm instance id from terraform state" >&2; exit 1; }
[[ -n "$IDS" ]] || { echo "ERROR: no instances found in terraform state" >&2; exit 1; }

EXPECTED=$(( $(wc -w <<<"${NONREALM_IDS:-}" | xargs) + 1 ))
echo "Realm: $REALM_ID"
echo "Clients: ${NONREALM_IDS:-<none>}"
echo "Expected nodes: $EXPECTED"

# ----- Wait for EC2 checks and SSM Online -----
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

# ----- Run redcli on the realm via SSM -----
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

# ----- Summary (also to GitHub summary when available) -----
{
  echo "### Infinia functional verification"
  echo
  echo "- Realm instance: \`$REALM_ID\`"
  echo "- Expected nodes (TF): \`$EXPECTED\`"
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

# ----- Health gates -----
[[ "$STATE" == "running" ]] || { echo "ERROR: cluster state is '$STATE' (want 'running')" >&2; exit 1; }
[[ "${EVICTED:-0}" -eq 0 ]] || { echo "ERROR: evicted CATs: $EVICTED" >&2; exit 1; }
[[ "${COUNT:-0}" -eq "$EXPECTED" ]] || { echo "ERROR: node count mismatch: expected $EXPECTED, got ${COUNT:-0}" >&2; exit 1; }

echo "Cluster verification OK ✅"
