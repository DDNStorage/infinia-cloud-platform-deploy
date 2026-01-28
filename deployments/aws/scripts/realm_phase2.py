#!/usr/bin/env python3
"""
Run the post-boot realm steps via SSM on the realm node.

What it does on the realm instance (inside a single bash script):
  1) Wait (bounded) for inventory to reach the desired node count.
  2) redcli realm config generate/update (with retries).
  3) redcli user login realm_admin -p <ADMIN_PW> (with retries).
  4) redcli license install -a <LICENSE_KEY> -y  (idempotent).
  5) redcli cluster create c1 -S=false -z -f     (idempotent).
  6) redcli cluster show                         (non-fatal if it fails).

Dependencies (local runner): boto3
  pip install boto3

Permissions required by the runner's AWS identity:
  - ssm:SendCommand
  - ssm:GetCommandInvocation
  - ssm:DescribeInstanceInformation
  - ec2:DescribeInstances
"""

import argparse
import base64
import os
import sys
import time
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError


PHASE2_BASH = r"""#!/usr/bin/env bash
# CI-safe: avoid 'pipefail' because early redcli commands can fail before API is ready.
set -eu
export REDCLI_NO_TTY=1

LOG=/var/log/red-phase2-tf.log
exec > >(tee -a "$LOG") 2>&1

: "${ADMIN_PW:?missing ADMIN_PW}"
: "${LICENSE_KEY:?missing LICENSE_KEY}"
: "${WANT:?missing WANT}"

echo "[phase2] start $(date -Is)"

# --- (A) Wait for local control-plane to be reachable enough to accept login ---
# Try a lightweight HTTPS probe on localhost (best-effort) before attempting login.
TRIES=0
until curl -kfsS https://127.0.0.1:443/redsetup/v1/system/status -o /dev/null || curl -kfsS https://localhost:443/redsetup/v1/system/status -o /dev/null; do
  TRIES=$((TRIES+1))
  [ "$TRIES" -ge 60 ] && break  # ~10 minutes max here
  echo "[phase2] waiting for local service (probe) try=$TRIES/60"
  sleep 10
done

# --- (B) Login first (bounded retries) ---
TRIES=0
until redcli user login realm_admin -p "$ADMIN_PW" >/dev/null 2>&1; do
  TRIES=$((TRIES+1))
  [ "$TRIES" -ge 30 ] && { echo "[phase2] FATAL: login failed after retries"; exit 1; }
  echo "[phase2] login retry $TRIES/30"
  sleep 10
done
echo "[phase2] login OK"

# --- (C) Now that we're authenticated, generate/update realm config ---
TRIES=0
until redcli realm config generate >/dev/null 2>&1; do
  TRIES=$((TRIES+1))
  [ "$TRIES" -ge 8 ] && { echo "[phase2] WARN: realm config generate failed after retries"; break; }
  echo "[phase2] realm config generate retry $TRIES/8"
  sleep 8
done

# Ensure file exists then update (with retries)
[ -s realm_config.yaml ] || redcli realm config generate >/dev/null 2>&1 || true
TRIES=0
until redcli realm config update -f realm_config.yaml >/dev/null 2>&1; do
  TRIES=$((TRIES+1))
  [ "$TRIES" -ge 8 ] && { echo "[phase2] WARN: realm config update failed after retries"; break; }
  echo "[phase2] realm config update retry $TRIES/8"
  sleep 8
done

# --- (D) License (idempotent) ---
redcli license show >/dev/null 2>&1 || redcli license install -a "$LICENSE_KEY" -y
redcli license show || true

# --- (E) Optional bounded wait for inventory (authenticated now) ---
TRIES=0
while :; do
  nodes="$(redcli inventory show 2>/dev/null | awk '/^[[:space:]]*Nodes:/ {print $2; exit}')"
  [ -z "$nodes" ] && nodes=0
  echo "[phase2] inventory Nodes=$nodes want=$WANT try=$TRIES"
  [ "$nodes" -ge "$WANT" ] && break
  TRIES=$((TRIES+1))
  [ "$TRIES" -ge 120 ] && { echo "[phase2] inventory wait timeout; proceeding"; break; }
  sleep 10
done

# --- (F) Cluster create (idempotent; accept already-exists/running) ---
OUT="$(redcli cluster create c1 -S=false -z -f 2>&1)" || true
echo "$OUT"
echo "$OUT" | grep -qiE 'already exists|created|is running' || true

# --- (G) Final status (non-fatal) ---
redcli cluster show || true
echo "[phase2] done $(date -Is)"
"""

def parse_args():
    p = argparse.ArgumentParser(description="Run realm phase-2 via SSM.")
    p.add_argument("--region", default=os.getenv("AWS_REGION") or os.getenv("AWS_DEFAULT_REGION") or "us-east-1")
    p.add_argument("--instance-id", help="Realm EC2 instance id. If omitted, will select latest with tag Role=realm (and Deployment if provided).")
    p.add_argument("--deployment", help="Optional Deployment tag to narrow instance selection.")
    p.add_argument("--want", type=int, required=True, help="Expected total node count (realm + nonrealm).")
    p.add_argument("--admin", required=True, help="realm_admin password.")
    p.add_argument("--license", required=True, help="Realm license key.")
    p.add_argument("--timeout-sec", type=int, default=2700, help="Overall SSM command timeout (default 2700s).")
    p.add_argument("--poll-sec", type=int, default=5, help="Polling interval for SSM status (default 5s).")
    return p.parse_args()


def ec2_client(region):
    return boto3.client("ec2", region_name=region)


def ssm_client(region):
    return boto3.client("ssm", region_name=region)


def find_realm_instance_id(ec2, deployment=None):
    filters = [
        {"Name": "tag:Role", "Values": ["realm"]},
        {"Name": "instance-state-name", "Values": ["pending", "running", "stopping", "stopped"]},
    ]
    if deployment:
        filters.append({"Name": "tag:Deployment", "Values": [deployment]})

    resp = ec2.describe_instances(Filters=filters)
    instances = []
    for r in resp.get("Reservations", []):
        for i in r.get("Instances", []):
            instances.append(i)

    if not instances:
        return None

    # pick latest LaunchTime
    instances.sort(key=lambda x: x.get("LaunchTime", datetime(1970, 1, 1, tzinfo=timezone.utc)), reverse=True)
    return instances[0]["InstanceId"]


def get_ec2_state(ec2, instance_id):
    try:
        resp = ec2.describe_instances(InstanceIds=[instance_id])
        return resp["Reservations"][0]["Instances"][0]["State"]["Name"]
    except Exception:
        return "unknown"


def wait_ec2_running(ec2, instance_id, max_tries=180, sleep_s=5):
    print("[tf] waiting for EC2 to be running…")
    for _ in range(max_tries):
        st = get_ec2_state(ec2, instance_id)
        print(f"[tf] EC2 state: {st}")
        if st == "running":
            return True
        time.sleep(sleep_s)
    return False


def get_ssm_ping(ssm, instance_id):
    try:
        resp = ssm.describe_instance_information(
            Filters=[{"Key": "InstanceIds", "Values": [instance_id]}]
        )
        info = resp.get("InstanceInformationList", [])
        if not info:
            return "None"
        return info[0].get("PingStatus", "None")
    except Exception:
        return "None"


def wait_ssm_online(ssm, instance_id, max_tries=180, sleep_s=5):
    print("[tf] waiting for SSM Online…")
    for _ in range(max_tries):
        ping = get_ssm_ping(ssm, instance_id)
        print(f"[tf] SSM PingStatus: {ping}")
        if ping == "Online":
            return True
        time.sleep(sleep_s)
    return False


def build_ssm_commands(script_b64, admin_pw, license_key, want_nodes):
    # Force bash explicitly on the remote side.
    # 1) write the base64 script
    # 2) chmod
    # 3) execute with env and bash -lc
    return [
        f"echo {script_b64} | base64 -d > /tmp/phase2.sh",
        "chmod +x /tmp/phase2.sh",
        f"ADMIN_PW='{admin_pw}' LICENSE_KEY='{license_key}' WANT='{want_nodes}' bash -lc '/tmp/phase2.sh'",
    ]


def send_phase2(ssm, instance_id, region, admin_pw, license_key, want_nodes, timeout_sec, poll_sec):
    script_b64 = base64.b64encode(PHASE2_BASH.encode("utf-8")).decode("ascii")
    params = {"commands": build_ssm_commands(script_b64, admin_pw, license_key, want_nodes)}

    resp = ssm.send_command(
        DocumentName="AWS-RunShellScript",
        InstanceIds=[instance_id],
        Parameters=params,
        TimeoutSeconds=timeout_sec,
    )
    cmd_id = resp["Command"]["CommandId"]
    print(f"[tf] SSM CommandId={cmd_id}")

    # poll
    max_iters = max(1, int(timeout_sec / poll_sec))
    for _ in range(max_iters):
        try:
            inv = ssm.get_command_invocation(CommandId=cmd_id, InstanceId=instance_id)
            status = inv.get("Status", "Pending")
        except ClientError as e:
            # Race; occasionally returns InvocationDoesNotExist until agent picks it up
            if e.response["Error"]["Code"] == "InvocationDoesNotExist":
                status = "Pending"
            else:
                raise
        print(f"[tf] SSM status: {status}")
        if status == "Success":
            print("[tf] Phase-2 completed successfully.")
            return 0
        if status in ("Failed", "Cancelled", "TimedOut"):
            print("----- Remote output -----")
            try:
                inv = ssm.get_command_invocation(CommandId=cmd_id, InstanceId=instance_id)
                print(inv.get("StatusDetails", ""))
                # show up to 4k of each stream for quick triage
                stdout = inv.get("StandardOutputContent", "")[:4000]
                stderr = inv.get("StandardErrorContent", "")[:4000]
                if stdout:
                    print(stdout)
                if stderr:
                    print(stderr)
            except Exception:
                pass
            return 1
        time.sleep(poll_sec)

    print("[tf] Timed out waiting for Phase-2 SSM command.")
    return 2


def main():
    args = parse_args()
    print(f"[tf] realm_phase2: REGION={args.region} WANT={args.want} DEPLOYMENT={args.deployment or ''} INSTANCE_ID={args.instance_id or '<auto>'}")

    ec2 = ec2_client(args.region)
    ssm = ssm_client(args.region)

    instance_id = args.instance_id
    if not instance_id:
        instance_id = find_realm_instance_id(ec2, args.deployment)
        if not instance_id:
            print(f"[tf] ERROR: No realm instance found by tags Role=realm"
                  f"{', Deployment='+args.deployment if args.deployment else ''}.", file=sys.stderr)
            return 3
    print(f"[tf] Using INSTANCE_ID={instance_id}")

    if not wait_ec2_running(ec2, instance_id):
        print("[tf] ERROR: instance never reached 'running'", file=sys.stderr)
        return 4

    if not wait_ssm_online(ssm, instance_id):
        print("[tf] ERROR: SSM never reached 'Online'", file=sys.stderr)
        return 5

    rc = send_phase2(
        ssm=ssm,
        instance_id=instance_id,
        region=args.region,
        admin_pw=args.admin,
        license_key=args.license,
        want_nodes=args.want,
        timeout_sec=args.timeout_sec,
        poll_sec=args.poll_sec,
    )
    return rc


if __name__ == "__main__":
    sys.exit(main())
