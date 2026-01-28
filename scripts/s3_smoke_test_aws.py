#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Infinia S3 API smoke test via AWS SSM

Implements your Ansible flow exactly (tenant 'red', realm path 'red/red/redobj'):
  redcli user login realm_admin -p <pw>
  redcli user add s3_test_user -p Adminpassword -r red -t red
  redcli user grant s3_test_user red/red -t red
  redcli s3 access add s3_test_user -t red -r red/red/redobj -e 10y [with cluster]

Enhancements:
- Cluster handling: auto-selects cluster if redcli prints "Auto Selecting cluster: <name>"
  (you can override with --cluster-name)
- Health gate (inventory presence) unless --skip-health-gate
- **Listener + inventory driven endpoint discovery for :8111**:
  * If bound to a specific IP -> probe that
  * If bound to wildcard (*, 0.0.0.0, ::) -> parse inventory node hostnames (ip-10-0-1-XYZ -> 10.0.1.XYZ)
    and probe those, plus realm's ENI IPs
- Short, visible SSM calls (no long "InProgress" hangs)
"""

import argparse
import datetime
import os
import random
import re
import sys
import time
import shlex
from typing import Optional, Dict, List, Tuple

import boto3


def eprint(*a, **k): print(*a, file=sys.stderr, **k)


def write_github_summary(content: str):
    """Write content to GitHub Actions step summary if running in GitHub Actions"""
    summary_file = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary_file:
        try:
            with open(summary_file, 'a', encoding='utf-8') as f:
                f.write(content + '\n')
        except Exception as e:
            eprint(f"Warning: Could not write to GitHub summary: {e}")
    else:
        eprint("Not running in GitHub Actions - summary not written")


# ----------------------------- EC2 helpers ----------------------------- #

def find_instances_by_tag(ec2, tag_key: str, tag_value: str, states=("running",)) -> List[dict]:
    insts: List[dict] = []
    paginator = ec2.get_paginator("describe_instances")
    for page in paginator.paginate(
        Filters=[
            {"Name": f"tag:{tag_key}", "Values": [tag_value]},
            {"Name": "instance-state-name", "Values": list(states)},
        ]
    ):
        for r in page.get("Reservations", []):
            for i in r.get("Instances", []):
                insts.append(i)
    return insts


def get_all_instance_ips(i: dict) -> List[str]:
    ips = []
    if i.get("PrivateIpAddress"): ips.append(i["PrivateIpAddress"])
    if i.get("PublicIpAddress"): ips.append(i["PublicIpAddress"])
    for eni in i.get("NetworkInterfaces", []):
        for p in eni.get("PrivateIpAddresses", []):
            ip = p.get("PrivateIpAddress")
            if ip: ips.append(ip)
    # dedupe, preserve order
    seen = set(); out = []
    for ip in ips:
        if ip and ip not in seen:
            seen.add(ip); out.append(ip)
    return out


# ----------------------------- SSM helpers ----------------------------- #

def ssm_run_bash(ssm, instance_ids, script: str, comment: str,
                 timeout_sec=180, poll_sec=3) -> Dict[str, Dict[str, str]]:
    """Run a small bash script via AWS-RunShellScript and wait; returns per-instance results."""
    if isinstance(instance_ids, str):
        instance_ids = [instance_ids]

    wrapped = [f"bash -lc {shlex.quote(script)}"]
    resp = ssm.send_command(
        DocumentName="AWS-RunShellScript",
        InstanceIds=instance_ids,
        Comment=comment,
        Parameters={"commands": wrapped},
    )
    cmd_id = resp["Command"]["CommandId"]
    print(f"[SSM] {comment} → CommandId={cmd_id}", file=sys.stderr)

    deadline = time.time() + timeout_sec
    results: Dict[str, Optional[Dict[str, str]]] = {iid: None for iid in instance_ids}
    last = {iid: None for iid in instance_ids}
    while time.time() < deadline:
        done = True
        for iid in instance_ids:
            if results[iid] is not None:
                continue
            try:
                inv = ssm.get_command_invocation(CommandId=cmd_id, InstanceId=iid)
            except ssm.exceptions.InvocationDoesNotExist:
                done = False
                continue
            status = inv.get("Status")
            if status != last[iid]:
                print(f"[SSM] {iid} status: {status}", file=sys.stderr)
                last[iid] = status
            if status in ("Success", "Failed", "Cancelled", "TimedOut"):
                results[iid] = {
                    "Status": status,
                    "StdOut": inv.get("StandardOutputContent", ""),
                    "StdErr": inv.get("StandardErrorContent", ""),
                }
            else:
                done = False
        if done:
            break
        time.sleep(poll_sec)

    for iid in instance_ids:
        if results[iid] is None:
            results[iid] = {"Status": "TimedOut", "StdOut": "", "StdErr": ""}

    return results  # type: ignore[return-value]


# ----------------------------- Parsing helpers ----------------------------- #

def parse_redcli_creds_from_table(text: str) -> Tuple[str, str]:
    key_match = re.search(r"│\s*S3_KEY\s*│\s*([^\s│]+)\s*│", text)
    sec_match = re.search(r"│\s*S3_SECRET\s*│\s*([^\s│]+)\s*│", text)
    return (key_match.group(1).strip() if key_match else "",
            sec_match.group(1).strip() if sec_match else "")


def parse_auto_selected_cluster(text: str) -> Optional[str]:
    m = re.search(r"Auto Selecting cluster:\s*([A-Za-z0-9._-]+)", text)
    return m.group(1) if m else None


def parse_inventory_ips_from_table(inventory_text: str) -> List[str]:
    """
    Parse hostnames like 'ip-10-0-1-165' from the inventory table and convert to '10.0.1.165'
    """
    ips: List[str] = []
    for hn in re.findall(r"\bip-(\d{1,3})-(\d{1,3})-(\d{1,3})-(\d{1,3})\b", inventory_text):
        ip = ".".join(hn)
        ips.append(ip)
    # dedupe, preserve order
    seen = set(); out = []
    for ip in ips:
        if ip not in seen:
            seen.add(ip); out.append(ip)
    return out


# ----------------------------- Main ----------------------------- #

def main() -> int:
    ap = argparse.ArgumentParser(description="Infinia S3 API smoke test (Ansible-parity + smart endpoint discovery)")
    ap.add_argument("--region", required=True)
    ap.add_argument("--admin-password", required=True)
    ap.add_argument("--realm-tag-key", default="Role")
    ap.add_argument("--realm-tag-value", default="realm")
    ap.add_argument("--client-tag-key", default="Role")
    ap.add_argument("--client-tag-value", default="client")

    ap.add_argument("--endpoint-port", type=int, default=8111)
    ap.add_argument("--endpoint-host", default="", help="Host override (skip discovery)")
    ap.add_argument("--no-verify-ssl", action="store_true")
    ap.add_argument("--timeout-sec", type=int, default=900)
    ap.add_argument("--verbose", action="store_true")

    ap.add_argument("--skip-health-gate", action="store_true",
                    help="Do not wait for inventory presence before minting")
    ap.add_argument("--cluster-name", default="",
                    help="Cluster name to use for redcli (-c/--cluster). If omitted, rely on auto-selection.")

    args = ap.parse_args()

    session = boto3.Session(region_name=args.region)
    ec2 = session.client("ec2")
    ssm = session.client("ssm")

    # Discover realm
    realms = find_instances_by_tag(ec2, args.realm_tag_key, args.realm_tag_value, states=("running",))
    if not realms:
        eprint(f"❌ No running realm instances with {args.realm_tag_key}={args.realm_tag_value}")
        return 2
    realm = realms[0]
    realm_id = realm["InstanceId"]
    eprint(f"Realm (for credential minting): {realm_id}")

    # Probe redcli path
    probe_script = r"""
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:/opt/bin:/opt/local/bin
REDCLI="$(command -v redcli || true)"
if [ -z "$REDCLI" ]; then
  for d in /opt/red/bin /opt/infinia/bin /usr/local/red/bin /usr/local/infinia/bin; do
    if [ -x "$d/redcli" ]; then REDCLI="$d/redcli"; break; fi
  done
fi
[ -z "$REDCLI" ] && { echo "NO_REDCLI"; exit 127; }
echo "$REDCLI"
"""
    res = ssm_run_bash(ssm, realm_id, probe_script, "Probe redcli path", timeout_sec=60)[realm_id]
    if res["Status"] != "Success":
        eprint("❌ Could not probe redcli path on realm")
        eprint("STDERR:\n" + res["StdErr"]); eprint("STDOUT:\n" + res["StdOut"])
        return 3
    redcli_path = res["StdOut"].strip().splitlines()[-1].strip()
    if redcli_path == "NO_REDCLI" or not redcli_path:
        eprint("❌ redcli not found on realm PATH/common dirs")
        return 3
    eprint(f"[realm] using redcli at: {redcli_path}")

    # Optional health gate: wait for inventory presence & capture inventory text for later IP parsing
    inventory_text = ""
    if not args.skip_health_gate:
        gate_deadline = time.time() + args.timeout_sec
        while time.time() < gate_deadline:
            gate_script = fr"""
set -euo pipefail
REDCLI="{redcli_path}"
ADMIN_PW="{args.admin_password}"
"$REDCLI" user login realm_admin -p "$ADMIN_PW" >/dev/null 2>&1 || true
INV="$("$REDCLI" inventory show 2>/dev/null || true)"
echo "===INV==="
echo "$INV"
"""
            g = ssm_run_bash(ssm, realm_id, gate_script, "Inventory gate", timeout_sec=90)[realm_id]
            if g["Status"] == "Success":
                so = g["StdOut"] or ""
                inventory_text = so
                m = re.search(r"^\s*Nodes:\s*(\d+)\s*$", so, re.MULTILINE)
                if m and int(m.group(1)) >= 1:
                    if args.verbose:
                        eprint("[gate] inventory snippet:")
                        for ln in [l for l in (so.splitlines()) if l.strip()][:20]:
                            eprint("  " + ln)
                    eprint("[gate] inventory present; proceeding")
                    break
            eprint("[gate] inventory not present; sleeping 20s…")
            time.sleep(20)
        else:
            eprint("❌ Inventory gate timed out")
            return 4

    # Mint creds (exact Ansible logic), possibly with cluster
    attempts, delay = 10, 20
    s3_key = s3_secret = ""
    last_out = ""
    cluster_flag = f'-c "{args.cluster_name}" ' if args.cluster_name else ""
    for i in range(1, attempts + 1):
        eprint(f"[realm] Mint attempt {i}/{attempts}")
        mint_script = fr"""
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:/opt/bin:/opt/local/bin
REDCLI="{redcli_path}"
ADMIN_PW="{args.admin_password}"

echo "🔐 Logging in as realm_admin..."
"$REDCLI" user login realm_admin -p "$ADMIN_PW"

"$REDCLI" user add s3_test_user -p Adminpassword -r red -t red >/dev/null 2>&1 || true
"$REDCLI" user grant s3_test_user red/red -t red >/dev/null 2>&1 || true

echo "🪪 Creating S3 access for s3_test_user..."
OUTPUT="$("$REDCLI" s3 access add {cluster_flag}s3_test_user -t red -r red/red/redobj -e 10y 2>&1 || true)"
echo "$OUTPUT"

# Emit parse-friendly markers
echo "===PARSE==="
echo "$OUTPUT" | sed -n 's/.*S3_KEY[[:space:]]*│[[:space:]]*\\([^[:space:]│]\\+\\).*/S3_KEY=\\1/p' | head -n1
echo "$OUTPUT" | sed -n 's/.*S3_SECRET[[:space:]]*│[[:space:]]*\\([^[:space:]│]\\+\\).*/S3_SECRET=\\1/p' | head -n1
"""
        r = ssm_run_bash(ssm, realm_id, mint_script, "Create S3 access (realm)", timeout_sec=180)[realm_id]
        out = (r["StdOut"] or "") + ("\n" + r["StdErr"] if r["StdErr"] else "")
        last_out = out
        if args.verbose:
            lines = [ln for ln in out.splitlines() if ln.strip()][:160]
            eprint("[realm] mint output (trimmed):")
            for ln in lines:
                eprint("  " + ln)

        if r["Status"] == "Success":
            # Prefer explicit table
            k, s = parse_redcli_creds_from_table(out)
            # If absent, try markers
            if not k or not s:
                mk = re.search(r"^S3_KEY=([^\s]+)$", out, re.MULTILINE)
                ms = re.search(r"^S3_SECRET=([^\s]+)$", out, re.MULTILINE)
                if mk: k = mk.group(1)
                if ms: s = ms.group(1)
            if k and s:
                s3_key, s3_secret = k, s
                # Learn cluster name if redcli auto-selected one
                if not args.cluster_name:
                    auto = parse_auto_selected_cluster(out)
                    if auto:
                        eprint(f"[realm] auto-selected cluster: {auto}")
                break

        if i < attempts:
            eprint(f"[realm] Retry in {delay}s…")
            time.sleep(delay)

    if not (s3_key and s3_secret):
        eprint("❌ Failed to mint S3 credentials after retries")
        if last_out:
            eprint("Last output (trimmed):")
            for ln in [l for l in last_out.splitlines() if l.strip()][:160]:
                eprint("  " + ln)

        # Write failure summary to GitHub Actions
        failure_summary = [
            "## 🚨 Infinia S3 Smoke Test - FAILED",
            "",
            f"**Test Time:** {datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')} UTC",
            f"**Region:** {args.region}",
            "",
            "### ❌ Credential Minting Failed",
            "",
            "Failed to mint S3 credentials after multiple retries.",
            "",
            "**Last output:**",
            "```",
            (last_out[:800] + "..." if len(last_out) > 800 else last_out) if last_out else "No output",
            "```"
        ]
        write_github_summary('\n'.join(failure_summary))
        return 4

    eprint(f"S3_KEY parsed: {s3_key[:4]}… (masked)")
    eprint("S3_SECRET parsed: **** (masked)")

    # Discover clients
    clients = find_instances_by_tag(ec2, args.client_tag_key, args.client_tag_value, states=("running",))
    client_ids = [i["InstanceId"] for i in clients]
    if not client_ids:
        eprint(f"❌ No running clients with {args.client_tag_key}={args.client_tag_value}")
        return 5

    # Use only the first client to avoid issues with multiple clients
    if len(client_ids) > 1:
        eprint(f"Found {len(client_ids)} clients: {', '.join(client_ids)}")
        eprint(f"Using only the first client: {client_ids[0]}")
        client_ids = [client_ids[0]]
    else:
        eprint(f"Client: {client_ids[0]}")

    # Endpoint candidates (listener + inventory driven, override if provided)
    if args.endpoint_host:
        candidates = [args.endpoint_host]
    else:
        # 1) Realm: which addrs listen on 8111?
        listen_script = r"""
set -euo pipefail
if command -v ss >/dev/null 2>&1; then
  ss -tlnH '( sport = :8111 )' | awk '{print $4}'
elif command -v netstat >/dev/null 2>&1; then
  netstat -tln | awk '$4 ~ /:8111$/ {print $4}'
fi
"""
        listen = ssm_run_bash(ssm, realm_id, listen_script, "Discover reds3 listener addrs", timeout_sec=40)[realm_id]
        bound_hosts = []
        if listen["Status"] == "Success":
            for ln in (listen["StdOut"] or "").splitlines():
                h = ln.strip()
                if not h:
                    continue
                # h like "*:8111", "0.0.0.0:8111", "10.0.1.165:8111", "[::]:8111"
                if h.startswith('['):
                    host = h.split(']')[0][1:]
                else:
                    host = h.rsplit(':', 1)[0]
                bound_hosts.append(host)

        # 2) Inventory-derived node IPs
        inv_ips = parse_inventory_ips_from_table(inventory_text or "")

        # 3) Realm ENI IPs
        realm_ips = get_all_instance_ips(realm)

        # Build final candidates:
        candidates: List[str] = []
        # a) any specific bound addresses (skip wildcards)
        for bh in bound_hosts:
            if bh and bh not in ("*", "0.0.0.0", "::") and bh not in candidates:
                candidates.append(bh)
        # b) if wildcard or empty, try inventory node IPs
        if (not bound_hosts) or any(b in ("*", "0.0.0.0", "::") for b in bound_hosts):
            for ip in inv_ips:
                if ip not in candidates:
                    candidates.append(ip)
        # c) also add realm ENI IPs as a fallback
        for ip in realm_ips:
            if ip not in candidates:
                candidates.append(ip)

    if not candidates:
        eprint("❌ No endpoint candidates (could not resolve any IPs for :8111)")
        return 6

    # Prep creds on the first client
    probe_client = client_ids[0]
    no_verify = "--no-verify-ssl" if args.no_verify_ssl else ""
    prep_script = f"""
set -euo pipefail
mkdir -p /home/ubuntu/.aws && chmod 700 /home/ubuntu/.aws
cat > /home/ubuntu/.aws/credentials <<'EOF'
[default]
aws_access_key_id={s3_key}
aws_secret_access_key={s3_secret}
EOF
echo READY
"""
    prep = ssm_run_bash(ssm, probe_client, prep_script, "Prep creds on probe client", timeout_sec=60)[probe_client]
    if prep["Status"] != "Success":
        eprint("❌ Failed to prepare credentials on probe client")
        eprint(prep["StdErr"])
        return 7

    # Probe endpoints quickly from the client
    chosen_host = ""
    tried = []
    for host in candidates:
        endpoint = f"https://{host}:{args.endpoint_port}"
        tried.append(endpoint)
        probe_script = f"""
set -euo pipefail
export AWS_SHARED_CREDENTIALS_FILE=/home/ubuntu/.aws/credentials
aws {no_verify} --endpoint-url="{endpoint}" s3api list-buckets >/dev/null 2>&1 && echo OK || echo NO
"""
        pr = ssm_run_bash(ssm, probe_client, probe_script, f"Probe {endpoint}", timeout_sec=40)[probe_client]
        if pr["Status"] == "Success" and "OK" in pr["StdOut"]:
            chosen_host = host
            eprint(f"Selected endpoint: {endpoint}")
            break

    if not chosen_host:
        eprint("❌ No working endpoint found. Tried:")
        for ep in tried: eprint(f"  - {ep}")
        return 8

    endpoint_url = f"https://{chosen_host}:{args.endpoint_port}"

    # Fan out S3 test on all clients
    now = datetime.datetime.utcnow().strftime("%Y%m%d%H%M%S")
    bucket = f"infinia-smoke-{now}-{random.randint(1000,9999)}"
    fan_script = f"""
set -euo pipefail
export AWS_SHARED_CREDENTIALS_FILE=/home/ubuntu/.aws/credentials
TS=$(date +%Y%m%d%H%M%S)
FNAME="test-${{TS}}.txt"
echo "S3 test file created at $TS" > "/home/ubuntu/$FNAME"
aws {no_verify} --endpoint-url="{endpoint_url}" s3api create-bucket --bucket "{bucket}" || true
aws {no_verify} --endpoint-url="{endpoint_url}" s3 cp "/home/ubuntu/$FNAME" "s3://{bucket}/"
LIST=$(aws {no_verify} --endpoint-url="{endpoint_url}" s3api list-objects-v2 --bucket "{bucket}" --query "Contents[].Key" --output text || true)
echo "LIST:$LIST"
echo "$LIST" | grep -q "$FNAME" && echo OK || echo FAIL
"""
    fan = ssm_run_bash(ssm, client_ids, fan_script, "Infinia S3 smoke test", timeout_sec=args.timeout_sec)
    failed = False

    # Prepare GitHub Actions summary
    summary_lines = [
        "## 🧪 Infinia S3 Smoke Test Results",
        "",
        f"**Test Time:** {datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')} UTC",
        f"**Region:** {args.region}",
        f"**Endpoint:** {endpoint_url}",
        f"**Bucket:** {bucket}",
        ""
    ]

    for iid, r in fan.items():
        print(f"---- Client {iid} ({r['Status']}) ----")
        print(r["StdOut"])

        if r["Status"] != "Success" or "OK" not in r["StdOut"]:
            eprint(f"❌ S3 smoke test failed on client {iid}")
            eprint(r["StdErr"])
            failed = True
            summary_lines.extend([
                f"### ❌ Client {iid} - FAILED",
                f"**Status:** {r['Status']}",
                "**Error:**",
                "```",
                r["StdErr"][:500] + ("..." if len(r["StdErr"]) > 500 else ""),
                "```",
                ""
            ])
        else:
            summary_lines.extend([
                f"### ✅ Client {iid} - PASSED",
                f"**Status:** {r['Status']}",
                "**Output:**",
                "```",
                r["StdOut"][:300] + ("..." if len(r["StdOut"]) > 300 else ""),
                "```",
                ""
            ])

    if failed:
        summary_lines.extend([
            "## 🚨 Test Result: FAILED",
            "",
            "One or more clients failed the S3 smoke test. Please check the error details above."
        ])
        write_github_summary('\n'.join(summary_lines))
        return 9

    summary_lines.extend([
        "## ✅ Test Result: PASSED",
        "",
        "All clients successfully completed the S3 smoke test!"
    ])
    write_github_summary('\n'.join(summary_lines))

    print("✅ S3 smoke test passed on all clients")
    return 0


if __name__ == "__main__":
    sys.exit(main())
