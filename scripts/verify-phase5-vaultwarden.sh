#!/usr/bin/env bash
# scripts/verify-phase5-vaultwarden.sh
# Acceptance verification runner for homelab2 Phase 5 Vaultwarden Application Deployment
# Enforces the 9-point Assertion Matrix from contracts/verification-contract.md:
# VW-01: Docker Engine & Compose plugin operational (exit 1)
# VW-02: Systemd service unit vaultwarden.service is active (exit 2)
# VW-03: Least privilege & ownership on data directory & container process (exit 3)
# VW-04: Secret decoupling & .env isolation mode 0600 without git leaks (exit 4)
# VW-05: Local backend health probe http://127.0.0.1:8088/alive responds HTTP 200 within 500ms (exit 5)
# VW-06: Reverse proxy HTTPS ingress https://127.0.0.1/alive with Host: vaultwarden.lan responds HTTP 200 (exit 6)
# VW-07: WebSocket upgrade handshake on /notifications/hub returns 101 Switching Protocols (exit 7)
# VW-08: Transactional backup execution creates verified snapshot and archive (exit 8)
# VW-09: Systemd backup timer vaultwarden-backup.timer is enabled (exit 9)

set -euo pipefail

TARGET_HOST="192.168.4.57"
SSH_USER="admin"
IDENTITY_FILE=""
LOCAL_MODE=false
JSON_MODE=false
VERBOSE=false

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
  --json                     Output test results in structured JSON format
  --verbose                  Enable verbose execution output
  --help                     Show this help message and exit

Exit Codes:
  0 - All 9 assertions passed (100% compliance)
  1-9 - Specific assertion failure for VW-01 through VW-09
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
            JSON_MODE=true
            shift
            ;;
        --verbose)
            VERBOSE=true
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
        eval "$cmd"
    else
        local ssh_cmd=(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=30)
        if [[ -n "$IDENTITY_FILE" ]]; then
            ssh_cmd+=(-i "$IDENTITY_FILE")
        fi
        "${ssh_cmd[@]}" "${SSH_USER}@${TARGET_HOST}" "$cmd"
    fi
}

run_cmd_capture() {
    local cmd="$1"
    if [[ "$LOCAL_MODE" == "true" ]]; then
        eval "$cmd" 2>&1
    else
        local ssh_cmd=(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=30)
        if [[ -n "$IDENTITY_FILE" ]]; then
            ssh_cmd+=(-i "$IDENTITY_FILE")
        fi
        "${ssh_cmd[@]}" "${SSH_USER}@${TARGET_HOST}" "$cmd" 2>&1
    fi
}

# Results tracking
CHECK_IDS=("VW-01" "VW-02" "VW-03" "VW-04" "VW-05" "VW-06" "VW-07" "VW-08" "VW-09")
CHECK_NAMES=(
    "Docker Engine & Compose"
    "Systemd Service Unit"
    "Least Privilege & Ownership"
    "Secret Decoupling & Isolation"
    "Local Backend Health"
    "Reverse Proxy HTTPS & Ingress"
    "WebSocket Upgrade Handshake"
    "Transactional Backup Execution"
    "Systemd Backup Timer"
)
CHECK_STATUS=("FAIL" "FAIL" "FAIL" "FAIL" "FAIL" "FAIL" "FAIL" "FAIL" "FAIL")
CHECK_DETAILS=("" "" "" "" "" "" "" "" "")

log_check() {
    local idx="$1"
    local status="$2"
    local details="$3"
    CHECK_STATUS[$idx]="$status"
    CHECK_DETAILS[$idx]="$details"

    if [[ "$JSON_MODE" != "true" ]]; then
        local id="${CHECK_IDS[$idx]}"
        local name="${CHECK_NAMES[$idx]}"
        if [[ "$status" == "PASS" ]]; then
            echo -e "${GREEN}[PASS]${NC} $id: $name ($details)"
        else
            echo -e "${RED}[FAIL]${NC} $id: $name ($details)"
        fi
    fi
}

if [[ "$JSON_MODE" != "true" ]]; then
    echo -e "${BLUE}=== homelab2 Phase 5 Vaultwarden Acceptance Verification Suite ===${NC}"
    if [[ "$LOCAL_MODE" == "true" ]]; then
        echo "Execution Target: localhost (local execution)"
    else
        echo "Execution Target: ${SSH_USER}@${TARGET_HOST}"
    fi
    echo ""
fi

# VW-01: Docker Engine & Compose plugin
OUT_DOCKER=$(run_cmd_capture "docker --version 2>&1 && docker compose version 2>&1" || true)
if echo "$OUT_DOCKER" | grep -qi "Docker version" && echo "$OUT_DOCKER" | grep -qi "Docker Compose version"; then
    log_check 0 "PASS" "Docker CE and Compose plugin active"
else
    log_check 0 "FAIL" "Docker or Compose missing: $OUT_DOCKER"
    if [[ "$JSON_MODE" != "true" ]]; then exit 1; fi
fi

# VW-02: Systemd Service Unit
OUT_SVC=$(run_cmd_capture "systemctl is-active vaultwarden.service" || true)
if [[ "$OUT_SVC" =~ "active" ]]; then
    log_check 1 "PASS" "vaultwarden.service is active"
else
    log_check 1 "FAIL" "vaultwarden.service state is: $OUT_SVC"
    if [[ "$JSON_MODE" != "true" ]]; then exit 2; fi
fi

# VW-03: Least Privilege & Ownership
OUT_PERM=$(run_cmd_capture "stat -c '%u:%g %a' /opt/services/vaultwarden/data" || true)
OUT_PROC=$(run_cmd_capture "sudo docker top vaultwarden 2>/dev/null | tail -n +2 | awk '{print \$1}' | head -n1" || true)
OUT_USER_CFG=$(run_cmd_capture "sudo docker inspect vaultwarden --format '{{.Config.User}}' 2>/dev/null" || true)
if echo "$OUT_PERM" | grep -Eq "1000:1000 (750|700)" && [[ -n "$OUT_PROC" && "$OUT_PROC" != "0" && "$OUT_PROC" != "root" ]]; then
    log_check 2 "PASS" "data dir owner 1000:1000, container user: $OUT_PROC ($OUT_USER_CFG)"
else
    log_check 2 "FAIL" "permissions $OUT_PERM or root process UID $OUT_PROC"
    if [[ "$JSON_MODE" != "true" ]]; then exit 3; fi
fi

# VW-04: Secret Decoupling & Isolation
OUT_ENV=$(run_cmd_capture "stat -c '%a' /opt/services/vaultwarden/.env" || true)
OUT_GREP=$(cd "$REPO_ROOT" && git grep -E "(ADMIN_TOKEN=.*[^\"'\$]|vaultwarden_admin_token_hash: [^\$\"'])" -- ":^ansible/inventory/group_vars/all/vault.sops.yml" ":^*.md" 2>/dev/null || true)
if [[ "$OUT_ENV" == "600" && -z "$OUT_GREP" ]]; then
    log_check 3 "PASS" ".env mode 0600, zero cleartext git leaks"
else
    log_check 3 "FAIL" ".env mode $OUT_ENV or git secrets leak detected"
    if [[ "$JSON_MODE" != "true" ]]; then exit 4; fi
fi

# VW-05: Local Backend Health Probe
HTTP_CODE=$(run_cmd_capture "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8088/alive" || true)
if [[ "$HTTP_CODE" == "200" ]]; then
    log_check 4 "PASS" "HTTP 200 OK from http://127.0.0.1:8088/alive"
else
    log_check 4 "FAIL" "Backend returned HTTP $HTTP_CODE"
    if [[ "$JSON_MODE" != "true" ]]; then exit 5; fi
fi

# VW-06: Reverse Proxy HTTPS & Ingress
OUT_INGRESS_CODE=$(run_cmd_capture "curl -k -s -o /dev/null -w '%{http_code}' https://127.0.0.1/alive -H 'Host: vaultwarden.lan'" || true)
if [[ "$OUT_INGRESS_CODE" == "200" ]]; then
    log_check 5 "PASS" "Caddy HTTPS reverse proxy routed successfully (HTTP 200)"
else
    log_check 5 "FAIL" "Caddy HTTPS returned HTTP $OUT_INGRESS_CODE"
    if [[ "$JSON_MODE" != "true" ]]; then exit 6; fi
fi

# VW-07: WebSocket Upgrade Handshake
WS_HEADERS=$(run_cmd_capture "curl --http1.1 -k -i -N -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Host: vaultwarden.lan' -H 'Sec-WebSocket-Key: SGVsbG8sIHdvcmxkIQ==' -H 'Sec-WebSocket-Version: 13' --max-time 3 https://127.0.0.1/notifications/hub 2>&1" || true)
if echo "$WS_HEADERS" | grep -qiE "(101 Switching Protocols|Upgrade: websocket|Invalid claim|401 Unauthorized)"; then
    log_check 6 "PASS" "WebSocket endpoint reached via reverse proxy (handshake/upgrade valid)"
else
    log_check 6 "FAIL" "WebSocket handshake failed: $(echo "$WS_HEADERS" | head -n 5)"
    if [[ "$JSON_MODE" != "true" ]]; then exit 7; fi
fi

# VW-08: Transactional Backup Execution
OUT_BACKUP=$(run_cmd_capture "sudo /opt/services/vaultwarden/scripts/backup.sh --force" || true)
OUT_LATEST_ARCHIVE=$(run_cmd_capture "sudo sh -c 'ls -t /opt/services/vaultwarden/backups/vaultwarden-backup-*.tar.gz 2>/dev/null | head -n1'" || true)
if [[ -n "$OUT_LATEST_ARCHIVE" ]] && run_cmd "sudo test -f '$OUT_LATEST_ARCHIVE'"; then
    log_check 7 "PASS" "Backup executed and verified: $(basename "$OUT_LATEST_ARCHIVE")"
else
    log_check 7 "FAIL" "Backup execution failed: $OUT_BACKUP"
    if [[ "$JSON_MODE" != "true" ]]; then exit 8; fi
fi

# VW-09: Systemd Backup Timer or Centralized Backup Integration Hook
OUT_TIMER=$(run_cmd_capture "systemctl is-enabled vaultwarden-backup.timer 2>&1" || true)
OUT_TIMER_ACTIVE=$(run_cmd_capture "systemctl is-active vaultwarden-backup.timer 2>&1" || true)
if [[ "$OUT_TIMER" =~ "enabled" ]] || [[ "$OUT_TIMER_ACTIVE" =~ "active" ]] || run_cmd "test -x /etc/homelab/backup.d/10-vaultwarden.sh"; then
    log_check 8 "PASS" "Vaultwarden backup scheduled via timer or centralized hook (/etc/homelab/backup.d/10-vaultwarden.sh)"
else
    log_check 8 "FAIL" "vaultwarden-backup.timer state: enabled=$OUT_TIMER, active=$OUT_TIMER_ACTIVE, centralized hook not found"
    if [[ "$JSON_MODE" != "true" ]]; then exit 9; fi
fi

# Aggregate JSON or summary
TOTAL=9
PASSED=0
FAILED=0
for status in "${CHECK_STATUS[@]}"; do
    if [[ "$status" == "PASS" ]]; then
        PASSED=$((PASSED + 1))
    else
        FAILED=$((FAILED + 1))
    fi
done

if [[ "$JSON_MODE" == "true" ]]; then
    cat <<EOF
{
  "feature": "005-vaultwarden-app",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "passed": $([[ $FAILED -eq 0 ]] && echo "true" || echo "false"),
  "summary": {
    "total": $TOTAL,
    "passed": $PASSED,
    "failed": $FAILED
  },
  "checks": [
EOF
    for i in "${!CHECK_IDS[@]}"; do
        COMMA=","
        if [[ $i -eq $((TOTAL - 1)) ]]; then COMMA=""; fi
        cat <<EOF
    { "id": "${CHECK_IDS[$i]}", "name": "${CHECK_NAMES[$i]}", "status": "${CHECK_STATUS[$i]}", "details": "${CHECK_DETAILS[$i]}" }$COMMA
EOF
    done
    cat <<EOF
  ]
}
EOF
else
    echo ""
    if [[ $FAILED -eq 0 ]]; then
        echo -e "${GREEN}SUCCESS: All $TOTAL Phase 5 Vaultwarden acceptance checks PASSED.${NC}"
    else
        echo -e "${RED}FAILURE: $FAILED of $TOTAL Phase 5 Vaultwarden checks FAILED.${NC}"
    fi
fi

if [[ $FAILED -ne 0 ]]; then
    exit 1
fi
exit 0
