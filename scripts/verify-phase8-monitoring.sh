#!/usr/bin/env bash
# scripts/verify-phase8-monitoring.sh
# Acceptance verification runner for homelab2 Phase 8: Platform Monitoring & Alerting (ntfy & Healthchecks)
# Enforces the 10-point Assertion Matrix from contracts/verification-contract.md:
# MON-01: Secret isolation & zero secrets in Git (exit 1)
# MON-02: Global catch-all systemd failure hooks & recursion guards (exit 2)
# MON-03: Zero-touch healthchecks.io reconciliation & registry (exit 3)
# MON-04: Scheduled maintenance job instrumentation & homelab-hc-run (exit 4)
# MON-05: Composite health sweep service & 5-minute heartbeat timer (exit 5)
# MON-06: Physical disk SMART alert hook & storage monitoring (exit 6)
# MON-07: Alert deduplication, cooldown suppression & recovery state machine (exit 7)
# MON-08: Live ntfy.sh & healthchecks.io connectivity (exit 8)
# MON-09: Offsite Restic backup coverage of monitoring config & secrets (exit 9)
# MON-10: Zero self-hosted monitoring containers & clean journal logs (exit 10)

set -euo pipefail

TARGET_HOST="192.168.4.57"
SSH_USER="admin"
IDENTITY_FILE=""
LOCAL_MODE=false
JSON_OUTPUT=false

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] [TARGET_HOST]

Options:
  -h, --host <IP|HOSTNAME>   Target host to verify (default: $TARGET_HOST)
  -u, --user <USERNAME>      SSH user for test connection (default: $SSH_USER)
  -i, --identity <KEY_PATH>  SSH identity file (private key)
  --local                    Run assertions directly against localhost
  --json                     Emit structured JSON results
  --help                     Show this help message and exit

Exit Codes:
  0 - All 10 assertions passed (100% compliance)
  1-10 - Specific assertion failure for MON-01 through MON-10
EOF
    exit 0
}

if SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)"; then
    REPO_ROOT="$SCRIPT_DIR"
else
    REPO_ROOT="$(pwd)"
fi
INVENTORY_FILE="${REPO_ROOT}/ansible/inventory/hosts.yml"

if [[ -f "$INVENTORY_FILE" ]]; then
    PARSED_HOST=$(grep -E 'ansible_host:' "$INVENTORY_FILE" | head -n1 | awk '{print $2}' || true)
    PARSED_USER=$(grep -E 'ansible_user:' "$INVENTORY_FILE" | head -n1 | awk '{print $2}' || true)
    if [[ -n "$PARSED_HOST" ]]; then TARGET_HOST="$PARSED_HOST"; fi
    if [[ -n "$PARSED_USER" ]]; then SSH_USER="$PARSED_USER"; fi
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--host)
            TARGET_HOST="$2"
            shift 2
            ;;
        -u|--user)
            SSH_USER="$2"
            shift 2
            ;;
        -i|--identity)
            IDENTITY_FILE="$2"
            shift 2
            ;;
        --local)
            LOCAL_MODE=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            TARGET_HOST="$1"
            shift
            ;;
    esac
done

# Auto-detect local execution if running on fidelacchius
if [[ "$LOCAL_MODE" != "true" && "$(uname -n 2>/dev/null || echo '')" == "fidelacchius" ]]; then
    LOCAL_MODE=true
fi

run_cmd() {
    local cmd="$1"
    if [[ "$LOCAL_MODE" == "true" ]]; then
        bash -c "$cmd"
    else
        local ssh_cmd=(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15)
        if [[ -n "$IDENTITY_FILE" ]]; then
            ssh_cmd+=(-i "$IDENTITY_FILE")
        fi
        "${ssh_cmd[@]}" "${SSH_USER}@${TARGET_HOST}" "$cmd"
    fi
}

run_cmd_capture() {
    local cmd="$1"
    if [[ "$LOCAL_MODE" == "true" ]]; then
        bash -c "$cmd" 2>&1 || true
    else
        local ssh_cmd=(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15)
        if [[ -n "$IDENTITY_FILE" ]]; then
            ssh_cmd+=(-i "$IDENTITY_FILE")
        fi
        "${ssh_cmd[@]}" "${SSH_USER}@${TARGET_HOST}" "$cmd" 2>&1 || true
    fi
}

TOTAL_ASSERTIONS=10
PASSED_COUNT=0
FAILED_COUNT=0
FIRST_FAIL_CODE=0

ASSERTION_IDS=("MON-01" "MON-02" "MON-03" "MON-04" "MON-05" "MON-06" "MON-07" "MON-08" "MON-09" "MON-10")
ASSERTION_NAMES=(
    "Secret Isolation & Zero Secrets in Git"
    "Global Systemd Failure Hooks & Recursion Guards"
    "Zero-Touch Healthchecks.io Reconciliation & Registry"
    "Scheduled Maintenance Job Instrumentation & Wrapper"
    "Composite Health Sweep & 5-Minute Heartbeat Timer"
    "Physical Disk SMART Alert Hook & Storage Monitoring"
    "Alert Deduplication, Cooldown & Recovery State Machine"
    "Live Outbound ntfy.sh & healthchecks.io Connectivity"
    "Offsite Restic Backup Coverage of Config & Secrets"
    "Zero Self-Hosted Monitoring Containers & Clean Logs"
)
ASSERTION_STATUS=("" "" "" "" "" "" "" "" "" "")
ASSERTION_DURATIONS=(0 0 0 0 0 0 0 0 0 0)
ASSERTION_DETAILS=("" "" "" "" "" "" "" "" "" "")

START_TIME=$(date +%s%N 2>/dev/null || date +%s)

record_result() {
    local idx="$1"
    local status="$2"
    local duration="$3"
    local details="${4:-}"

    ASSERTION_STATUS[$idx]="$status"
    ASSERTION_DURATIONS[$idx]="$duration"
    ASSERTION_DETAILS[$idx]="$details"

    if [[ "$status" == "PASS" ]]; then
        PASSED_COUNT=$((PASSED_COUNT + 1))
        if [[ "$JSON_OUTPUT" != "true" ]]; then
            echo -e "${GREEN}PASS${NC} (${duration}ms)"
        fi
    else
        FAILED_COUNT=$((FAILED_COUNT + 1))
        if [[ "$FIRST_FAIL_CODE" -eq 0 ]]; then
            FIRST_FAIL_CODE=$((idx + 1))
        fi
        if [[ "$JSON_OUTPUT" != "true" ]]; then
            echo -e "${RED}FAIL${NC} (${duration}ms): $details"
        fi
    fi
}

if [[ "$JSON_OUTPUT" != "true" ]]; then
    echo "================================================================================"
    echo "  fidelacchius Phase 8 Verification: Platform Monitoring & Alerting"
    echo "  Target Host: ${TARGET_HOST} (Local: ${LOCAL_MODE})"
    echo "================================================================================"
fi

# MON-01: Secret Isolation & Zero Secrets in Git
a_start=$(date +%s%N 2>/dev/null || date +%s)
if [[ "$JSON_OUTPUT" != "true" ]]; then
    echo -n "Checking MON-01: Secret isolation & zero secrets in Git... "
fi
mon01_ok=true
mon01_err=""

env_stat=$(run_cmd_capture "sudo stat -c '%a:%u:%g' /etc/homelab/monitoring.env" | tr -d '\r\n')
if [[ "$env_stat" != "600:0:0" ]]; then
    mon01_ok=false
    mon01_err="monitoring.env permissions $env_stat != 600:0:0"
fi

example_stat=$(run_cmd_capture "stat -c '%a:%u:%g' /etc/homelab/monitoring.env.example" | tr -d '\r\n')
if [[ "$example_stat" != "644:0:0" ]]; then
    mon01_ok=false
    mon01_err="monitoring.env.example permissions $example_stat != 644:0:0"
fi

if [[ -f "${REPO_ROOT}/ansible/inventory/group_vars/all/vault.yml.example" ]]; then
    if ! grep -q "vault_ntfy_topic:" "${REPO_ROOT}/ansible/inventory/group_vars/all/vault.yml.example"; then
        mon01_ok=false
        mon01_err="vault_ntfy_topic missing from vault.yml.example"
    fi
fi

# Check git leaks in tracked files
git_leaks=$(git -C "$REPO_ROOT" grep -iE '(vault_ntfy_token:\s*["'"'"'][^"'"'"']+|vault_healthchecks_api_key:\s*["'"'"']hc_rw_[a-zA-Z0-9]+)' -- :^*.example :^specs/ :^ansible/inventory/group_vars/all/vault.yml 2>/dev/null || true)
if [[ -n "$git_leaks" ]]; then
    mon01_ok=false
    mon01_err="Real secrets detected in tracked git files"
fi

a_end=$(date +%s%N 2>/dev/null || date +%s)
a_dur=$(( (a_end - a_start) / 1000000 ))
if [[ "$mon01_ok" == "true" ]]; then
    record_result 0 "PASS" "$a_dur" "Permissions 0600/0644 verified, zero git leaks"
else
    record_result 0 "FAIL" "$a_dur" "$mon01_err"
fi

# MON-02: Global Systemd Failure Hooks & Recursion Guards
a_start=$(date +%s%N 2>/dev/null || date +%s)
if [[ "$JSON_OUTPUT" != "true" ]]; then
    echo -n "Checking MON-02: Global systemd failure hooks & recursion guards... "
fi
mon02_ok=true
mon02_err=""

hook_files=(
    "/etc/systemd/system/service.d/99-homelab-failure-alert.conf"
    "/etc/systemd/user/service.d/99-homelab-failure-alert.conf"
    "/etc/systemd/system/homelab-alert@.service"
    "/etc/systemd/user/homelab-alert@.service"
    "/etc/systemd/system/homelab-alert@.service.d/99-zz-no-recursion.conf"
    "/etc/systemd/user/homelab-alert@.service.d/99-zz-no-recursion.conf"
)
for f in "${hook_files[@]}"; do
    if ! run_cmd "test -f '$f'"; then
        mon02_ok=false
        mon02_err="Missing failure hook file: $f"
        break
    fi
done

if [[ "$mon02_ok" == "true" ]]; then
    sshd_onfail=$(run_cmd_capture "systemctl show sshd.service -p OnFailure --value" | tr -d '\r\n')
    if [[ "$sshd_onfail" != *"homelab-alert@sshd.service"* ]]; then
        mon02_ok=false
        mon02_err="sshd.service OnFailure is '$sshd_onfail', expected homelab-alert@sshd.service"
    fi

    guard_onfail=$(run_cmd_capture "systemctl show homelab-alert@sshd.service -p OnFailure --value" | tr -d '\r\n')
    if [[ -n "$guard_onfail" ]]; then
        mon02_ok=false
        mon02_err="Recursion guard breached: homelab-alert@sshd.service OnFailure is '$guard_onfail' (expected empty)"
    fi
fi

a_end=$(date +%s%N 2>/dev/null || date +%s)
a_dur=$(( (a_end - a_start) / 1000000 ))
if [[ "$mon02_ok" == "true" ]]; then
    record_result 1 "PASS" "$a_dur" "Global hooks active with verified recursion guards"
else
    record_result 1 "FAIL" "$a_dur" "$mon02_err"
fi

# MON-03: Zero-Touch Healthchecks.io Reconciliation & Registry
a_start=$(date +%s%N 2>/dev/null || date +%s)
if [[ "$JSON_OUTPUT" != "true" ]]; then
    echo -n "Checking MON-03: Zero-touch healthchecks.io reconciliation & checks.json... "
fi
mon03_ok=true
mon03_err=""

if ! run_cmd "test -x /usr/local/bin/homelab-hc-reconcile"; then
    mon03_ok=false
    mon03_err="/usr/local/bin/homelab-hc-reconcile is missing or not executable"
fi

catalog_check=$(run_cmd_capture "jq -e '.checks | length == 6 and (all(.channels == \"*\"))' /etc/homelab/monitoring/checks-catalog.json" || true)
if [[ "$mon03_ok" == "true" && "$catalog_check" != "true" ]]; then
    mon03_ok=false
    mon03_err="checks-catalog.json does not define 6 checks with channels: '*'"
fi

checks_stat=$(run_cmd_capture "sudo stat -c '%a:%u:%g' /var/lib/homelab/monitoring/checks.json" | tr -d '\r\n')
if [[ "$mon03_ok" == "true" && "$checks_stat" != "600:0:0" ]]; then
    mon03_ok=false
    mon03_err="/var/lib/homelab/monitoring/checks.json permissions $checks_stat != 600:0:0"
fi

if [[ "$mon03_ok" == "true" ]]; then
    checks_slug_count=$(run_cmd_capture "sudo jq '.checks | keys | length' /var/lib/homelab/monitoring/checks.json" | tr -d '\r\n')
    if [[ "$checks_slug_count" -lt 6 ]]; then
        mon03_ok=false
        mon03_err="checks.json contains $checks_slug_count cached checks, expected 6"
    fi
fi

a_end=$(date +%s%N 2>/dev/null || date +%s)
a_dur=$(( (a_end - a_start) / 1000000 ))
if [[ "$mon03_ok" == "true" ]]; then
    record_result 2 "PASS" "$a_dur" "Catalog valid and checks.json cached with 6 endpoints"
else
    record_result 2 "FAIL" "$a_dur" "$mon03_err"
fi

# MON-04: Scheduled Maintenance Job Instrumentation & Wrapper
a_start=$(date +%s%N 2>/dev/null || date +%s)
if [[ "$JSON_OUTPUT" != "true" ]]; then
    echo -n "Checking MON-04: Scheduled maintenance job drop-ins & homelab-hc-run... "
fi
mon04_ok=true
mon04_err=""

if ! run_cmd "test -x /usr/local/bin/homelab-hc-run && test -x /usr/local/bin/homelab-hc-ping"; then
    mon04_ok=false
    mon04_err="homelab-hc-run or homelab-hc-ping not executable"
fi

maintenance_units=(
    "homelab-backup.service"
    "homelab-backup-check.service"
    "vaultwarden-backup.service"
    "snapraid-sync.service"
    "snapraid-scrub.service"
)
for u in "${maintenance_units[@]}"; do
    if [[ "$mon04_ok" == "true" ]]; then
        hooks=$(run_cmd_capture "systemctl show '$u' -p ExecStartPre -p ExecStopPost --value" || true)
        if [[ "$hooks" != *"homelab-hc-ping"* ]]; then
            mon04_ok=false
            mon04_err="Unit $u does not have homelab-hc-ping in ExecStartPre/ExecStopPost"
            break
        fi
    fi
done

a_end=$(date +%s%N 2>/dev/null || date +%s)
a_dur=$(( (a_end - a_start) / 1000000 ))
if [[ "$mon04_ok" == "true" ]]; then
    record_result 3 "PASS" "$a_dur" "All 5 maintenance services instrumented via drop-ins"
else
    record_result 3 "FAIL" "$a_dur" "$mon04_err"
fi

# MON-05: Composite Health Sweep Service & 5-Minute Heartbeat Timer
a_start=$(date +%s%N 2>/dev/null || date +%s)
if [[ "$JSON_OUTPUT" != "true" ]]; then
    echo -n "Checking MON-05: Composite health sweep & heartbeat timer... "
fi
mon05_ok=true
mon05_err=""

timer_enabled=$(run_cmd_capture "systemctl is-enabled homelab-heartbeat.timer" | tr -d '\r\n')
timer_active=$(run_cmd_capture "systemctl is-active homelab-heartbeat.timer" | tr -d '\r\n')
if [[ "$timer_enabled" != "enabled" || "$timer_active" != "active" ]]; then
    mon05_ok=false
    mon05_err="homelab-heartbeat.timer status: enabled=$timer_enabled, active=$timer_active"
fi

if [[ "$mon05_ok" == "true" ]]; then
    if ! run_cmd "sudo /usr/local/bin/homelab-health-sweep"; then
        mon05_ok=false
        mon05_err="/usr/local/bin/homelab-health-sweep exited with non-zero status"
    fi
fi

a_end=$(date +%s%N 2>/dev/null || date +%s)
a_dur=$(( (a_end - a_start) / 1000000 ))
if [[ "$mon05_ok" == "true" ]]; then
    record_result 4 "PASS" "$a_dur" "Heartbeat timer active and health sweep exited cleanly"
else
    record_result 4 "FAIL" "$a_dur" "$mon05_err"
fi

# MON-06: Physical Disk SMART Alert Hook & Storage Monitoring
a_start=$(date +%s%N 2>/dev/null || date +%s)
if [[ "$JSON_OUTPUT" != "true" ]]; then
    echo -n "Checking MON-06: Physical disk SMART alert hook & smartd service... "
fi
mon06_ok=true
mon06_err=""

if ! run_cmd "test -x /usr/local/bin/homelab-smartd-alert"; then
    mon06_ok=false
    mon06_err="/usr/local/bin/homelab-smartd-alert missing or not executable"
fi

if [[ "$mon06_ok" == "true" ]]; then
    if ! run_cmd "grep -q -- '-M exec /usr/local/bin/homelab-smartd-alert' /etc/smartd.conf"; then
        mon06_ok=false
        mon06_err="/etc/smartd.conf does not configure -M exec /usr/local/bin/homelab-smartd-alert"
    fi
fi

if [[ "$mon06_ok" == "true" ]]; then
    smartd_active=$(run_cmd_capture "systemctl is-active smartd.service" | tr -d '\r\n')
    if [[ "$smartd_active" != "active" ]]; then
        mon06_ok=false
        mon06_err="smartd.service status is '$smartd_active' (expected active)"
    fi
fi

a_end=$(date +%s%N 2>/dev/null || date +%s)
a_dur=$(( (a_end - a_start) / 1000000 ))
if [[ "$mon06_ok" == "true" ]]; then
    record_result 5 "PASS" "$a_dur" "smartd.conf configured with alert hook and smartd is active"
else
    record_result 5 "FAIL" "$a_dur" "$mon06_err"
fi

# MON-07: Alert Deduplication, Cooldown Suppression & Recovery State Machine
a_start=$(date +%s%N 2>/dev/null || date +%s)
if [[ "$JSON_OUTPUT" != "true" ]]; then
    echo -n "Checking MON-07: Alert deduplication & recovery state machine... "
fi
mon07_ok=true
mon07_err=""

# Test deduplication by triggering 5 rapid failures
run_cmd "sudo rm -f /var/lib/homelab/monitoring/state/verify-flapping-test.json" >/dev/null 2>&1 || true
for _ in {1..5}; do
    run_cmd "sudo /usr/local/bin/homelab-ntfy --component verify-flapping-test --status failing --title 'Test Flap' --message 'Synthetic failure event'" >/dev/null 2>&1 || true
done

suppressed_cnt=$(run_cmd_capture "sudo jq -r '.suppressed_count // 0' /var/lib/homelab/monitoring/state/verify-flapping-test.json" | tr -d '\r\n')
if ! [[ "$suppressed_cnt" =~ ^[0-9]+$ ]] || [[ "$suppressed_cnt" -ne 4 ]]; then
    mon07_ok=false
    mon07_err="Deduplication failed: suppressed_count is $suppressed_cnt (expected 4)"
fi

if [[ "$mon07_ok" == "true" ]]; then
    # Trigger recovery
    run_cmd "sudo /usr/local/bin/homelab-ntfy --component verify-flapping-test --status ok --title 'Test Recovery' --message 'Resolved'" >/dev/null 2>&1 || true
    recovered_st=$(run_cmd_capture "sudo jq -r '.status // \"\"' /var/lib/homelab/monitoring/state/verify-flapping-test.json" | tr -d '\r\n')
    recovered_sc=$(run_cmd_capture "sudo jq -r '.suppressed_count // -1' /var/lib/homelab/monitoring/state/verify-flapping-test.json" | tr -d '\r\n')
    if [[ "$recovered_st" != "ok" || "$recovered_sc" != "0" ]]; then
        mon07_ok=false
        mon07_err="Recovery transition failed: status='$recovered_st', suppressed_count=$recovered_sc"
    fi
fi

# Clean up synthetic test state
run_cmd "sudo rm -f /var/lib/homelab/monitoring/state/verify-flapping-test.json" >/dev/null 2>&1 || true

a_end=$(date +%s%N 2>/dev/null || date +%s)
a_dur=$(( (a_end - a_start) / 1000000 ))
if [[ "$mon07_ok" == "true" ]]; then
    record_result 6 "PASS" "$a_dur" "5 simulated flaps suppressed (cnt=4) and recovery cleanly cleared state"
else
    record_result 6 "FAIL" "$a_dur" "$mon07_err"
fi

# MON-08: Live Outbound ntfy.sh & healthchecks.io Connectivity
a_start=$(date +%s%N 2>/dev/null || date +%s)
if [[ "$JSON_OUTPUT" != "true" ]]; then
    echo -n "Checking MON-08: Live ntfy.sh & healthchecks.io outbound connectivity... "
fi
mon08_ok=true
mon08_err=""

# Live dispatch test to ntfy
ntfy_test_res=$(run_cmd_capture "sudo /usr/local/bin/homelab-ntfy --component verify-connectivity-test --status test --title '[VERIFY] fidelacchius Connectivity Test' --message 'Automated verification check MON-08'" || true)
if run_cmd "grep -q 'ERROR: Failed to deliver alert' /var/log/messages 2>/dev/null" || [[ "$ntfy_test_res" =~ "ERROR" ]]; then
    mon08_ok=false
    mon08_err="Outbound ntfy delivery failed: $ntfy_test_res"
fi

# Healthchecks live endpoint connectivity test
hc_ping_test=$(run_cmd_capture "curl -fsS --retry 2 --connect-timeout 5 --max-time 10 https://hc-ping.com >/dev/null && echo 'OK'" || echo 'FAIL')
if [[ "$hc_ping_test" != *"OK"* ]]; then
    mon08_ok=false
    mon08_err="Outbound connectivity to https://hc-ping.com failed"
fi

a_end=$(date +%s%N 2>/dev/null || date +%s)
a_dur=$(( (a_end - a_start) / 1000000 ))
if [[ "$mon08_ok" == "true" ]]; then
    record_result 7 "PASS" "$a_dur" "Outbound ntfy.sh test alert and hc-ping.com reached successfully"
else
    record_result 7 "FAIL" "$a_dur" "$mon08_err"
fi

# MON-09: Offsite Restic Backup Coverage of Config & Secrets
a_start=$(date +%s%N 2>/dev/null || date +%s)
if [[ "$JSON_OUTPUT" != "true" ]]; then
    echo -n "Checking MON-09: Offsite Restic backup coverage of monitoring config & secrets... "
fi
mon09_ok=true
mon09_err=""

include_file="/etc/homelab/backup-include.txt"
if ! run_cmd "test -f '$include_file'"; then
    mon09_ok=false
    mon09_err="$include_file does not exist"
else
    if ! run_cmd "grep -Fxq '/etc/homelab' '$include_file'"; then
        mon09_ok=false
        mon09_err="/etc/homelab missing from $include_file"
    fi
    if ! run_cmd "grep -Fxq '/var/lib/homelab/monitoring/checks.json' '$include_file'"; then
        mon09_ok=false
        mon09_err="/var/lib/homelab/monitoring/checks.json missing from $include_file"
    fi
fi

a_end=$(date +%s%N 2>/dev/null || date +%s)
a_dur=$(( (a_end - a_start) / 1000000 ))
if [[ "$mon09_ok" == "true" ]]; then
    record_result 8 "PASS" "$a_dur" "/etc/homelab and checks.json included in Restic backup manifest"
else
    record_result 8 "FAIL" "$a_dur" "$mon09_err"
fi

# MON-10: Zero Self-Hosted Monitoring Containers & Clean Logs
a_start=$(date +%s%N 2>/dev/null || date +%s)
if [[ "$JSON_OUTPUT" != "true" ]]; then
    echo -n "Checking MON-10: Zero self-hosted monitoring containers & clean logs... "
fi
mon10_ok=true
mon10_err=""

containers=$(run_cmd_capture "docker ps -a --format '{{.Image}} {{.Names}}'" || true)
if echo "$containers" | grep -iE 'binwiederhier/ntfy|healthchecks/healthchecks' >/dev/null 2>&1; then
    mon10_ok=false
    mon10_err="Self-hosted monitoring container detected in docker ps -a"
fi

sweep_errors=$(run_cmd_capture "journalctl -u homelab-heartbeat.service -n 25 --no-pager" || true)
if echo "$sweep_errors" | grep -iE 'Traceback|panic:|syntax error|command not found' >/dev/null 2>&1; then
    mon10_ok=false
    mon10_err="Errors detected in homelab-heartbeat.service journal"
fi

a_end=$(date +%s%N 2>/dev/null || date +%s)
a_dur=$(( (a_end - a_start) / 1000000 ))
if [[ "$mon10_ok" == "true" ]]; then
    record_result 9 "PASS" "$a_dur" "Zero self-hosted containers and clean journal execution logs"
else
    record_result 9 "FAIL" "$a_dur" "$mon10_err"
fi

END_TIME=$(date +%s%N 2>/dev/null || date +%s)
TOTAL_DURATION_MS=$(( (END_TIME - START_TIME) / 1000000 ))

if [[ "$JSON_OUTPUT" == "true" ]]; then
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    cat <<EOF
{
  "timestamp": "$TIMESTAMP",
  "feature": "011-monitoring-ntfy-healthchecks",
  "target": "fidelacchius",
  "summary": {
    "total": $TOTAL_ASSERTIONS,
    "passed": $PASSED_COUNT,
    "failed": $FAILED_COUNT,
    "duration_ms": $TOTAL_DURATION_MS
  },
  "assertions": [
$(for i in "${!ASSERTION_IDS[@]}"; do
    comma=","
    if [[ $i -eq $((TOTAL_ASSERTIONS - 1)) ]]; then comma=""; fi
    echo "    {\"id\": \"${ASSERTION_IDS[$i]}\", \"name\": \"${ASSERTION_NAMES[$i]}\", \"status\": \"${ASSERTION_STATUS[$i]}\", \"duration_ms\": ${ASSERTION_DURATIONS[$i]}, \"details\": \"${ASSERTION_DETAILS[$i]}\"}$comma"
done)
  ]
}
EOF
else
    echo "================================================================================"
    if [[ $FAILED_COUNT -eq 0 ]]; then
        echo -e "${GREEN}✓ All 10 Platform Monitoring assertions passed successfully (100% compliance).${NC}"
    else
        echo -e "${RED}✗ $FAILED_COUNT assertion(s) failed out of $TOTAL_ASSERTIONS.${NC}"
    fi
    echo "================================================================================"
fi

exit $FIRST_FAIL_CODE
