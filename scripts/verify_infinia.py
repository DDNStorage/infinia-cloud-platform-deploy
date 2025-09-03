#!/usr/bin/env python3
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
    filters = [{'Name': 'instance-state-name', 'Values': ['running', 'pending']},
               {'Name': 'tag:Role', 'Values': [role]}]
    if DEPLOYMENT_TAG_KEY and DEPLOYMENT_TAG_VALUE:
        filters.append({'Name': f'tag:{DEPLOYMENT_TAG_KEY}', 'Values': [DEPLOYMENT_TAG_VALUE]})
    if AMI_ID:
        filters.append({'Name': 'image-id', 'Values': [AMI_ID]})
    resp = ec2.describe_instances(Filters=filters)
    ids = [i['InstanceId'] for r in resp.get('Reservations', []) for i in r.get('Instances', [])]
    return ids

realm_ids = find_instances('realm')
if not realm_ids:
    print("ERROR: no realm instance found (tag Role=realm).", file=sys.stderr)
    sys.exit(1)
realm_id = realm_ids[0]

nonrealm_ids = find_instances('nonrealm')
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
        for st in resp.get('InstanceStatuses', []):
            if st.get('InstanceStatus', {}).get('Status') == 'ok' and st.get('SystemStatus', {}).get('Status') == 'ok':
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
    # DescribeInstanceInformation supports a filter by InstanceIds
    try:
        resp = ssm.describe_instance_information(
            Filters=[{'Key': 'InstanceIds', 'Values': [instance_id]}]
        )
    except (BotoCoreError, ClientError):
        return False
    infos = resp.get('InstanceInformationList', [])
    return any(info.get('InstanceId') == instance_id and info.get('PingStatus') == 'Online' for info in infos)

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

# ---- build remote script (safe quoting) ----
pass_b64 = base64.b64encode(REALM_ADMIN_PASSWORD.encode("utf-8")).decode("ascii")
remote_lines = [
    "#!/usr/bin/env bash",
    "set -euo pipefail",
    "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
    f"PASS=$(printf '%s' '{pass_b64}' | base64 -d)",
    "redcli user login realm_admin -p \"$PASS\" >/dev/null 2>&1 || true",
    "INV=$(redcli inventory show 2>/dev/null || true)",
    "CLJSON=$( (redcli cluster show -o json || redcli cluster show --json) 2>/dev/null || true )",
    "echo '__INV_START__'",
    "echo \"$INV\"",
    "echo '__INV_END__'",
    "echo '__CLJSON_START__'",
    "echo \"$CLJSON\"",
    "echo '__CLJSON_END__'",
]

# Turn into AWS-RunShellScript commands: write a heredoc, then run it
commands = [
    "cat > /tmp/verify_infinia.sh <<'EOS'"
] + remote_lines + [
    "EOS",
    "bash /tmp/verify_infinia.sh"
]

print("Sending SSM command to realm…")
try:
    send = ssm.send_command(
        InstanceIds=[realm_id],
        DocumentName='AWS-RunShellScript',
        Parameters={'commands': commands}
    )
except (BotoCoreError, ClientError) as e:
    print(f"ERROR: send_command failed: {e}", file=sys.stderr)
    sys.exit(1)

cmd_id = send['Command']['CommandId']
print(f"CommandId: {cmd_id}")

# ---- poll for completion ----
status = "Pending"
while status in ("Pending", "InProgress", "Delayed"):
    try:
        inv = ssm.get_command_invocation(CommandId=cmd_id, InstanceId=realm_id)
        status = inv.get('Status', 'Unknown')
    except (BotoCoreError, ClientError):
        status = "Unknown"
    if status in ("Pending", "InProgress", "Delayed"):
        time.sleep(3)
    else:
        break

try:
    inv = ssm.get_command_invocation(CommandId=cmd_id, InstanceId=realm_id)
except (BotoCoreError, ClientError) as e:
    print(f"ERROR: get_command_invocation failed: {e}", file=sys.stderr)
    sys.exit(1)

print(f"SSM status: {inv.get('Status')}")
if inv.get('Status') != "Success":
    print(inv.get('StandardErrorContent', ''), file=sys.stderr)
    sys.exit(1)

stdout = inv.get('StandardOutputContent') or ""
# ---- parse outputs ----
inv_table = []
cljson_raw = []

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

# Parse node count from inventory summary line: "Nodes:    N"
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
print("Cluster verification OK ✅")
