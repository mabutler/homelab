#!/usr/bin/env bash
# scripts/verify-phase7-antigravity.sh
# Acceptance verification runner for fidelacchius Feature 007 (Target Host Antigravity & Remote Control)
# Enforces the 8-point Assertion Matrix from contracts/verification-suite-contract.md:
# AG-001: Antigravity CLI Binary Available (command -v agy && agy --version)
# AG-002: User Lingering Enabled (/var/lib/systemd/linger/admin exists)
# AG-003: Remote Control Service Active (systemctl --user is-active agy-remote-control.service)
# AG-004: Remote Control Status & Instance Registered (agy remote-control status contains homelab2-target)
# AG-005: Autonomous Settings & Perms Validated (toolPermission == "always-proceed", agentMode == "auto", mode 0600)
# AG-006: Host Git Workspace & Worktrees Ready (git rev-parse and worktree list)
# AG-007: Backup Registration Validated (backup-include.txt and backup-excludes.txt contain paths)
# AG-008: Zero Credentials in Version Control (git status clean of secret patterns)

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
  -u, --user <USERNAME>       SSH user for test connection (default: $SSH_USER)
  -i, --identity <KEY_PATH>   SSH identity file (private key)
  --local                     Run assertions directly against localhost
  --json                      Emit structured JSON results
  --help                      Show this help message and exit

Exit Codes:
  0 - All 8 assertions passed (100% compliance)
  1-8 - Specific assertion failure for AG-001 through AG-008
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

run_cmd() {
    local cmd="$1"
    if [[ "$LOCAL_MODE" == "true" ]]; then
        bash -c "$cmd"
    else
        local ssh_args=("-o" "BatchMode=yes" "-o" "StrictHostKeyChecking=accept-new" "-o" "ConnectTimeout=10")
        if [[ -n "$IDENTITY_FILE" ]]; then
            ssh_args+=("-i" "$IDENTITY_FILE")
        fi
        ssh "${ssh_args[@]}" "${SSH_USER}@${TARGET_HOST}" "$cmd"
    fi
}

# Run user-level command with user environment
run_user_cmd() {
    local cmd="$1"
    local wrapped_cmd="export XDG_RUNTIME_DIR=\"/run/user/\$(id -u)\"; export DBUS_SESSION_BUS_ADDRESS=\"unix:path=/run/user/\$(id -u)/bus\"; export PATH=\"\$HOME/.local/bin:/usr/local/bin:\$PATH\"; $cmd"
    run_cmd "$wrapped_cmd"
}

START_TIME=$(date +%s%N 2>/dev/null || date +%s)
TOTAL_ASSERTIONS=8
PASSED_COUNT=0
FAILED_COUNT=0

declare -a ASSERTION_IDS=("AG-001" "AG-002" "AG-003" "AG-004" "AG-005" "AG-006" "AG-007" "AG-008")
declare -a ASSERTION_NAMES=(
    "Antigravity CLI Binary Available"
    "User Lingering Enabled"
    "Remote Control Service Active"
    "Remote Control Status & Instance Registered"
    "Autonomous Settings & Perms Validated"
    "Host Git Workspace & Worktrees Ready"
    "Backup Registration Validated"
    "Zero Credentials in Version Control"
)
declare -a ASSERTION_STATUS=()
declare -a ASSERTION_DURATIONS=()

run_assertion() {
    local idx="$1"
    local id="${ASSERTION_IDS[$idx]}"
    local name="${ASSERTION_NAMES[$idx]}"
    local t_start
    t_start=$(date +%s%N 2>/dev/null || date +%s)
    local status="FAIL"

    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo -n "Checking $id: $name... "
    fi

    case "$id" in
        "AG-001")
            if run_user_cmd "command -v agy && agy --version" >/dev/null 2>&1; then
                status="PASS"
            fi
            ;;
        "AG-002")
            if run_cmd "test -f /var/lib/systemd/linger/admin" >/dev/null 2>&1; then
                status="PASS"
            fi
            ;;
        "AG-003")
            if run_user_cmd "systemctl --user is-active antigravity-cli-daemon.service agy-remote-control.service" 2>&1 | grep -q "^active"; then
                status="PASS"
            fi
            ;;
        "AG-004")
            local status_out
            status_out=$(run_user_cmd "agy remote-control status" 2>/dev/null || true)
            if echo "$status_out" | grep -q "homelab2-target"; then
                status="PASS"
            fi
            ;;
        "AG-005")
            local json_check
            local perms_check
            json_check=$(run_user_cmd "jq -e '.toolPermission == \"always-proceed\" and .agentMode == \"auto\"' ~/.gemini/antigravity-cli/settings.json" >/dev/null 2>&1 && echo "ok" || echo "fail")
            perms_check=$(run_user_cmd "stat -c '%a %U:%G' ~/.gemini/antigravity-cli/settings.json 2>/dev/null || stat -f '%Lp %Su:%Sg' ~/.gemini/antigravity-cli/settings.json 2>/dev/null || true")
            if [[ "$json_check" == "ok" ]] && echo "$perms_check" | grep -qE "600 admin:(admin|users)"; then
                status="PASS"
            fi
            ;;
        "AG-006")
            if run_user_cmd "git -C /home/admin/homelab2 rev-parse --is-inside-work-tree && git -C /home/admin/homelab2 worktree list" >/dev/null 2>&1; then
                status="PASS"
            fi
            ;;
        "AG-007")
            local inc_check
            local exc_check
            inc_check=$(run_cmd "grep -F '/home/admin/.gemini/oauth_creds.json' /etc/homelab/backup-include.txt" 2>/dev/null || true)
            exc_check=$(run_cmd "grep -F '/home/admin/.gemini/antigravity-cli/cache/**' /etc/homelab/backup-excludes.txt" 2>/dev/null || true)
            if [[ -n "$inc_check" && -n "$exc_check" ]]; then
                status="PASS"
            fi
            ;;
        "AG-008")
            local leaked_creds
            leaked_creds=$(run_user_cmd "git -C /home/admin/homelab2 status --porcelain 2>/dev/null | grep -E 'oauth_creds|google_accounts|\.env|id_ed25519'" || true)
            if [[ -z "$leaked_creds" ]]; then
                status="PASS"
            fi
            ;;
    esac

    local t_end
    t_end=$(date +%s%N 2>/dev/null || date +%s)
    local duration_ms=0
    if [[ "$t_end" =~ ^[0-9]+$ && "$t_start" =~ ^[0-9]+$ && "$t_end" -ge "$t_start" ]]; then
        duration_ms=$(( (t_end - t_start) / 1000000 ))
        if [[ $duration_ms -eq 0 && "$t_end" -ne "$t_start" ]]; then
            duration_ms=$(( (t_end - t_start) * 1000 ))
        fi
    fi

    ASSERTION_STATUS+=("$status")
    ASSERTION_DURATIONS+=("$duration_ms")

    if [[ "$status" == "PASS" ]]; then
        PASSED_COUNT=$((PASSED_COUNT + 1))
        if [[ "$JSON_OUTPUT" == "false" ]]; then
            echo -e "${GREEN}PASS${NC} (${duration_ms}ms)"
        fi
    else
        FAILED_COUNT=$((FAILED_COUNT + 1))
        if [[ "$JSON_OUTPUT" == "false" ]]; then
            echo -e "${RED}FAIL${NC} (${duration_ms}ms)"
            echo "ERROR: [$id] $name failed validation" >&2
        fi
    fi
}

if [[ "$JSON_OUTPUT" == "false" ]]; then
    echo -e "${BLUE}=== fidelacchius Feature 007 Acceptance Verification Suite ===${NC}"
    if [[ "$LOCAL_MODE" == "true" ]]; then
        echo "Execution Target: localhost (local execution)"
    else
        echo "Execution Target: ${SSH_USER}@${TARGET_HOST}"
    fi
    echo ""
fi

FIRST_FAIL_CODE=0
for i in "${!ASSERTION_IDS[@]}"; do
    run_assertion "$i"
    if [[ "${ASSERTION_STATUS[$i]}" != "PASS" && $FIRST_FAIL_CODE -eq 0 ]]; then
        FIRST_FAIL_CODE=$((i + 1))
    fi
done

END_TIME=$(date +%s%N 2>/dev/null || date +%s)
TOTAL_DURATION_MS=0
if [[ "$END_TIME" =~ ^[0-9]+$ && "$START_TIME" =~ ^[0-9]+$ && "$END_TIME" -ge "$START_TIME" ]]; then
    TOTAL_DURATION_MS=$(( (END_TIME - START_TIME) / 1000000 ))
    if [[ $TOTAL_DURATION_MS -eq 0 && "$END_TIME" -ne "$START_TIME" ]]; then
        TOTAL_DURATION_MS=$(( (END_TIME - START_TIME) * 1000 ))
    fi
fi

if [[ "$JSON_OUTPUT" == "true" ]]; then
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    cat <<EOF
{
  "timestamp": "$TIMESTAMP",
  "feature": "007-antigravity-remote-control",
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
    echo "    {\"id\": \"${ASSERTION_IDS[$i]}\", \"name\": \"${ASSERTION_NAMES[$i]}\", \"status\": \"${ASSERTION_STATUS[$i]}\", \"duration_ms\": ${ASSERTION_DURATIONS[$i]}}$comma"
done)
  ]
}
EOF
else
    echo ""
    if [[ $FAILED_COUNT -eq 0 ]]; then
        echo -e "${GREEN}✓ All 8 Antigravity remote control assertions passed successfully (100% compliance).${NC}"
    else
        echo -e "${RED}✗ $FAILED_COUNT assertion(s) failed out of $TOTAL_ASSERTIONS.${NC}"
    fi
fi

exit $FIRST_FAIL_CODE
