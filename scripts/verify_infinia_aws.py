#!/usr/bin/env python3
"""
Verify Infinia cluster via EC2 tags + SSM, with remote polling.

Required env:
  AWS_REGION (or REGION/AWS_DEFAULT_REGION)
  REALM_ADMIN_PASSWORD (or INFINIA_ADMIN_PASSWORD)

Optional env:
  AMI_ID
  DEPLOYMENT_TAG_KEY
  DEPLOYMENT_TAG_VALUE
  VERIFY_STRICT (default "1")
  INVENTORY_TIMEOUT_SEC (default "1800")
  INVENTORY_POLL_SEC (default "15")
"""

import os
import sys
import time
import json
import base64
import boto3
from botocore.exceptions import BotoCoreError, ClientError
import re


def env(name, default=None, required=False):
    v = os.environ.get(name, default)
    if required and not v:
        print(f"ERROR: missing env {name}", file=sys.stderr)
        sys.exit(1)
    return v


AWS_REGION = env("AWS_REGION", os.environ.get("REGION", os.environ.get("AWS_DEFAULT_REGION")), required=True)
REALM_ADMIN_PASSWORD = env("REALM_ADMIN_PASSWORD", os.environ.get("INFINIA_ADMIN_PASSWORD"), required=True)
AMI_ID = env("AMI_ID", "")
DEPLOYMENT_TAG_KEY = env("DEPLOYMENT_TAG_KEY", "")
DEPLOYMENT_TAG_VALUE = env("DEPLOYMENT_TAG_VALUE", "")
VERIFY_STRICT = env("VERIFY_STRICT", "1")  # "1" = enforce cluster_state/evicted when JSON available
INVENTORY_TIMEOUT_SEC = int(env("INVENTORY_TIMEOUT_SEC", "1800"))
INVENTORY_POLL_SEC = int(env("INVENTORY_POLL_SEC", "15"))

ec2 = boto3.client("ec2", region_name=AWS_REGION)
ssm = boto3.client("ssm", region_name=AWS_REGION)
sts = boto3.client("sts", region_name=AWS_REGION)

# ---- sanity ----
try:
    sts.get_caller_identity()
except Exception as e:
    print(f"ERROR: bad AWS credentials: {e}", file=sys.stderr)
    sys.exit(1)


def find_instances(role):
    filters = [
        {"Name": "instance-state-name", "Values": ["running", "pending"]},
        {"Name": "tag:Role", "Values": [role]},
    ]
    if DEPLOYMENT_TAG_KEY and DEPLOYMENT_TAG_VALUE:
        filters.append({"Name": f"tag:{DEPLOYMENT_TAG_KEY}", "Values": [DEPLOYMENT_TAG_VALUE]})
    if AMI_ID:
        filters.append({"Name": "image-id", "Values": [AMI_ID]})
    resp = ec2.describe_instances(Filters=filters)
    ids = [i["InstanceId"] for r in resp.get("Reservations", []) for i in r.get("Instances", [])]
    return ids


realm_ids = find_instances("realm")
if not realm_ids:
    print("ERROR: no realm instance found (tag Role=realm).", file=sys.stderr)
    sys.exit(1)
if len(realm_ids) > 1:
    print(f"WARN: multiple realms found; using first: {realm_ids}", file=sys.stderr)
realm_id = realm_ids[0]

nonrealm_ids = find_instances("nonrealm")
clients_str = " ".join(nonrealm_ids) if nonrealm_ids else "<none>"
expected_nodes = (len(nonrealm_ids) + 1)

print(f"Realm:   {realm_id}")
print(f"Clients: {clients_str}")
print(f"Expected node count: {expected_nodes}")


# ---- wait for EC2 checks OK ----
def wait_ec2_checks_ok(instance_ids, timeout=1800, poll=15):
    deadline = time.time() + timeout
    num = len(instance_ids)
    while True:
        resp = ec2.describe_instance_status(InstanceIds=instance_ids, IncludeAllInstances=True)
        ok = 0
        for st in resp.get("InstanceStatuses", []):
            if st.get("InstanceStatus", {}).get("Status") == "ok" and st.get("SystemStatus", {}).get("Status") == "ok":
                ok += 1
        print(f"EC2 checks OK: {ok} / {num}")
        if ok == num:
            return True
        if time.time() > deadline:
            print("ERROR: timeout waiting for EC2 checks", file=sys.stderr)
            return False
        time.sleep(poll)


ids_all = [realm_id] + nonrealm_ids
if not wait_ec2_checks_ok(ids_all):
    sys.exit(1)


# ---- wait for SSM Online ----
def is_ssm_online(instance_id):
    try:
        resp = ssm.describe_instance_information(Filters=[{"Key": "InstanceIds", "Values": [instance_id]}])
    except (BotoCoreError, ClientError):
        return False
    infos = resp.get("InstanceInformationList", [])
    return any(info.get("InstanceId") == instance_id and info.get("PingStatus") == "Online" for info in infos)


def wait_ssm_online(instance_id, timeout=600, poll=5):
    print(f"Waiting SSM Online: {instance_id}")
    deadline = time.time() + timeout
    while time.time() < deadline:
        if is_ssm_online(instance_id):
            print(f"SSM Online for {instance_id}")
            return True
        time.sleep(poll)
    print(f"ERROR: timeout waiting SSM for {instance_id}", file=sys.stderr)
    return False


for iid in ids_all:
    if not wait_ssm_online(iid):
        sys.exit(1)


# ---- build remote script with polling ----
pass_b64 = base64.b64encode(REALM_ADMIN_PASSWORD.encode("utf-8")).decode("ascii")
strict_flag = "1" if str(VERIFY_STRICT).strip() == "1" else "0"

remote_lines = [
    "#!/usr/bin/env bash",
    "set -euo pipefail",
    "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
    f"EXPECTED_NODES={expected_nodes}",
    f"STRICT={strict_flag}",
    f"TIMEOUT_SEC={INVENTORY_TIMEOUT_SEC}",
    f"POLL_SEC={INVENTORY_POLL_SEC}",
    f"PASS=$(printf '%s' '{pass_b64}' | base64 -d)",
    'deadline=$(( $(date +%s) + TIMEOUT_SEC ))',
    'last_inv=""',
    'last_json=""',
    'last_count=0',
    'last_state=""',
    'last_evicted=""',
    '',
    'login_once() {',
    '  redcli user login realm_admin -p "$PASS" >/dev/null 2>&1 || true',
    '}',
    'count_from_inv() {',
    '  # parse "Nodes:    N" from inventory table',
    '  awk \'/^[[:space:]]*Nodes:/ {print $2; exit}\'',
    '}',
    '',
    'login_once',
    'while :; do',
    '  INV="$(redcli inventory show 2>/dev/null || true)"',
    '  CNT="$(printf "%s\\n" "$INV" | count_from_inv)"',
    '  if [[ "$CNT" =~ ^[0-9]+$ ]]; then last_count="$CNT"; else last_count=0; fi',
    '  JSON="$( (redcli cluster show -o json || redcli cluster show --json) 2>/dev/null || true )"',
    '  STATE="$(jq -r \'.cluster_state // .state // empty\' <<<"$JSON" 2>/dev/null || true)"',
    '  EVICTED="$(jq \'([.cats[]? | select(.evicted==true)] | length) // 0\' <<<"$JSON" 2>/dev/null || echo 0)"',
    '  last_inv="$INV"; last_json="$JSON"; last_state="$STATE"; last_evicted="$EVICTED";',
    '  # success conditions',
    '  if (( last_count >= EXPECTED_NODES )); then',
    '    if [[ "$STRICT" == "1" ]]; then',
    '      if [[ "$last_state" == "running" && "${last_evicted:-0}" -eq 0 ]]; then',
    '        break',
    '      fi',
    '    else',
    '      break',
    '    fi',
    '  fi',
    '  # timeout?',
    '  now=$(date +%s)',
    '  if (( now >= deadline )); then',
    '    break',
    '  fi',
    '  sleep "$POLL_SEC"',
    'done',
    '',
    'echo "__INV_START__"',
    'printf "%s\\n" "$last_inv"',
    'echo "__INV_END__"',
    'echo "__INV_COUNT__${last_count}__INV_COUNT__"',
    'echo "__CLJSON_START__"',
    'printf "%s\\n" "$last_json"',
    'echo "__CLJSON_END__"',
    '',
    '# exit code: 0 if conditions satisfied, 1 otherwise',
    'rc=0',
    'if (( last_count < EXPECTED_NODES )); then rc=1; fi',
    'if [[ "$STRICT" == "1" && -n "$last_json" && "$last_state" != "running" ]]; then rc=1; fi',
    'if [[ "$STRICT" == "1" && -n "$last_json" && "${last_evicted:-0}" -ne 0 ]]; then rc=1; fi',
    'exit $rc',
]

# Commands for AWS-RunShellScript: write heredoc, then run it
commands = ["cat > /tmp/verify_infinia.sh <<'EOS'"] + remote_lines + ["EOS", "bash /tmp/verify_infinia.sh"]

print("Sending SSM command to realm…")
try:
    send = ssm.send_command(
        InstanceIds=[realm_id],
        DocumentName="AWS-RunShellScript",
        Parameters={"commands": commands},
        TimeoutSeconds=INVENTORY_TIMEOUT_SEC + 120,  # small buffer beyond loop timeout
    )
except (BotoCoreError, ClientError) as e:
    print(f"ERROR: send_command failed: {e}", file=sys.stderr)
    sys.exit(1)

cmd_id = send["Command"]["CommandId"]
print(f"CommandId: {cmd_id}")


# ---- robust poll for completion (handles InvocationDoesNotExist) ----
time.sleep(1)  # small grace period for consistency
final = None
deadline = time.time() + INVENTORY_TIMEOUT_SEC + 240  # SSM grace
while time.time() < deadline:
    try:
        inv = ssm.get_command_invocation(CommandId=cmd_id, InstanceId=realm_id)
        status = inv.get("Status", "Unknown")
    except ClientError as e:
        code = e.response.get("Error", {}).get("Code")
        if code == "InvocationDoesNotExist":
            time.sleep(2)
            continue
        print(f"ERROR: get_command_invocation failed: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: get_command_invocation error: {e}", file=sys.stderr)
        sys.exit(1)

    if status in ("Pending", "InProgress", "Delayed"):
        time.sleep(3)
        continue

    final = inv
    break

if not final:
    # last attempt before giving up
    try:
        final = ssm.get_command_invocation(CommandId=cmd_id, InstanceId=realm_id)
        status = final.get("Status", "Unknown")
    except Exception as e:
        print(f"ERROR: get_command_invocation still not available: {e}", file=sys.stderr)
        sys.exit(1)
else:
    status = final.get("Status", "Unknown")

print(f"SSM status: {status}")
stdout = final.get("StandardOutputContent") or ""
stderr = final.get("StandardErrorContent") or ""
if status != "Success":
    if stdout:
        print(stdout)
    if stderr:
        print(stderr, file=sys.stderr)
    # fall through to parse what we have, but exit non-zero at the end
    ssm_failed = True
else:
    ssm_failed = False


# ---- parse outputs ----
inv_table = []
cljson_raw = []
inv_count_marker = None
in_inv = in_json = False
for line in stdout.splitlines():
    if line.strip() == "__INV_START__":
        in_inv = True
        continue
    if line.strip() == "__INV_END__":
        in_inv = False
        continue
    if line.strip() == "__CLJSON_START__":
        in_json = True
        continue
    if line.strip() == "__CLJSON_END__":
        in_json = False
        continue
    if line.startswith("__INV_COUNT__") and line.endswith("__INV_COUNT__"):
        try:
            inv_count_marker = int(line[len("__INV_COUNT__"):-len("__INV_COUNT__")])
        except Exception:
            pass
        continue
    if in_inv:
        inv_table.append(line)
    if in_json:
        cljson_raw.append(line)

inventory_text = "\n".join(inv_table).strip()
cljson_text = "\n".join(cljson_raw).strip()

print("\n====== redcli inventory show ======")
print(inventory_text)
print("===================================\n")

# append to GitHub summary if available
summary_path = os.environ.get("GITHUB_STEP_SUMMARY", "")
if summary_path:
    with open(summary_path, "a", encoding="utf-8") as fh:
        fh.write("### Infinia Cluster Verification\n\n")
        fh.write(f"- Realm instance: `{realm_id}`\n")
        fh.write(f"- Expected nodes: `{expected_nodes}`\n\n")
        fh.write("<details><summary>redcli inventory show</summary>\n\n")
        fh.write("```text\n")
        fh.write(inventory_text + "\n")
        fh.write("```\n")
        fh.write("</details>\n")

# Parse node count (prefer explicit marker first)
if isinstance(inv_count_marker, int):
    inv_nodes = inv_count_marker
else:
    m = re.search(r"^\s*Nodes:\s*(\d+)\s*$", inventory_text, re.MULTILINE)
    inv_nodes = int(m.group(1)) if m else None

if inv_nodes is None:
    print("ERROR: could not parse node count from inventory", file=sys.stderr)
    sys.exit(1)

# Try parse cluster JSON for stricter checks
cl_state = None
cl_count = None
cl_evicted = None
if cljson_text and cljson_text.lower() != "null":
    try:
        j = json.loads(cljson_text)
        cl_state = j.get("cluster_state") or j.get("state")
        if "instances" in j and isinstance(j["instances"], list):
            cl_count = len(j["instances"])
        elif "nodes" in j and isinstance(j["nodes"], list):
            cl_count = len(j["nodes"])
        cats = j.get("cats") or []
        cl_evicted = sum(1 for c in cats if c.get("evicted") is True)
        print(f"Cluster state: {cl_state}")
        print(f"Cluster instances (JSON): {cl_count if cl_count is not None else 'n/a'}")
        print(f"Evicted CATs: {cl_evicted if cl_evicted is not None else 'n/a'}")
        if VERIFY_STRICT == "1":
            if cl_state != "running":
                print(f"ERROR: cluster_state={cl_state} (want running)", file=sys.stderr)
                sys.exit(1)
            if (cl_evicted or 0) != 0:
                print(f"ERROR: evicted CATs = {cl_evicted}", file=sys.stderr)
                sys.exit(1)
    except Exception:
        print("WARN: cluster JSON was not parseable; continuing with inventory check only.")

# Gate on count (prefer JSON count if present)
effective_count = cl_count if isinstance(cl_count, int) and cl_count > 0 else inv_nodes
if effective_count != expected_nodes:
    print(f"ERROR: node count mismatch (expected {expected_nodes}, got {effective_count})", file=sys.stderr)
    sys.exit(1)

print(f"Inventory node count: {inv_nodes}")
if ssm_failed:
    # Remote script signaled a timeout – we already printed inventory; still error out.
    print("ERROR: remote verification timed out before satisfying conditions", file=sys.stderr)
    sys.exit(1)

print("Cluster verification OK ✅")