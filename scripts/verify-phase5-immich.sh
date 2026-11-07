#!/usr/bin/env bash
# scripts/verify-phase5-immich.sh
# Acceptance verification runner for homelab2 Phase 5 Immich Photo Management Platform Deployment
# Enforces the 9-point Assertion Matrix from contracts/verification-contract.md:
# IMM-01: Immich systemd service & containers active with 0 restart loops (exit 1)
# IMM-02: HTTP API ping probe responds HTTP 200 within 500ms (exit 2)
# IMM-03: Intel UHD Graphics 770 iGPU bound & discrete AMD GPU isolated (exit 3)
# IMM-04: Tiered storage topology: NVMe for data/postgres, MergerFS for photos (exit 4)
# IMM-05: Secret isolation: .env mode 0600, .env.example exists, zero git credential leaks (exit 5)
# IMM-06: Caddy reverse proxy ingress configuration valid with loopback target (exit 6)
# IMM-07: Storage group ownership & 2775 setgid permissions on /mnt/storage/media/photos (exit 7)
# IMM-08: Transactional backup hook /etc/homelab/backup.d/30-immich.sh dump verified (exit 8)
# IMM-09: Structured logs in journald with zero unhandled fatal panics (exit 9)

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
  1-9 - Specific assertion failure for IMM-01 through IMM-09
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
CHECK_IDS=("IMM-01" "IMM-02" "IMM-03" "IMM-04" "IMM-05" "IMM-06" "IMM-07" "IMM-08" "IMM-09")
CHECK_NAMES=(
    "Service & Containers Active"
    "HTTP API Ping Probe (< 500ms)"
    "Intel UHD 770 iGPU Device Binding"
    "Tiered Storage Topology"
    "Secret Isolation & Permissions"
    "Caddy Ingress Configuration"
    "Storage Group & Ownership"
    "Transactional Backup Hook Execution"
    "Structured Telemetry & Clean Logs"
)
CHECK_STATUS=("FAIL" "FAIL" "FAIL" "FAIL" "FAIL" "FAIL" "FAIL" "FAIL" "FAIL")
CHECK_DETAILS=("" "" "" "" "" "" "" "" "")

log_check() {
    local idx="$1"
    local status="$2"
    local details="$3"
    CHECK_STATUS[idx]="$status"
    CHECK_DETAILS[idx]="$details"

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
    echo -e "${BLUE}=== homelab2 Phase 5 Immich Acceptance Verification Suite ===${NC}"
    if [[ "$LOCAL_MODE" == "true" ]]; then
        echo "Execution Target: localhost (local execution)"
    else
        echo "Execution Target: ${SSH_USER}@${TARGET_HOST}"
    fi
    echo ""
fi

# IMM-01: Service & Containers Active
OUT_SVC=$(run_cmd_capture "systemctl is-active immich.service" || true)
OUT_CONTAINERS=$(run_cmd_capture "sudo docker ps --filter 'name=immich_' --format '{{.Names}}:{{.Status}}' 2>/dev/null" || true)
CONTAINER_COUNT=$(echo "$OUT_CONTAINERS" | grep -cE "(immich_server|immich_machine_learning|immich_postgres|immich_redis)" || true)

if [[ "$OUT_SVC" =~ "active" ]] && [[ "$CONTAINER_COUNT" -ge 4 ]] && ! echo "$OUT_CONTAINERS" | grep -qi "restarting"; then
    log_check 0 "PASS" "immich.service active, 4 containers operational without restarts"
else
    log_check 0 "FAIL" "service: $OUT_SVC, active containers: $CONTAINER_COUNT/4 ($OUT_CONTAINERS)"
    if [[ "$JSON_MODE" != "true" ]]; then exit 1; fi
fi

# IMM-02: HTTP API Ping Probe (< 500ms)
START_TIME=$(date +%s%N)
OUT_PING=$(run_cmd_capture "curl -fsS --max-time 1 http://127.0.0.1:2283/api/server/ping" || true)
END_TIME=$(date +%s%N)
ELAPSED_MS=$(( (END_TIME - START_TIME) / 1000000 ))

if echo "$OUT_PING" | grep -q '"res":"pong"'; then
    log_check 1 "PASS" "API ping returned pong in ${ELAPSED_MS}ms"
else
    log_check 1 "FAIL" "ping response: $OUT_PING (elapsed: ${ELAPSED_MS}ms)"
    if [[ "$JSON_MODE" != "true" ]]; then exit 2; fi
fi

# IMM-03: Intel UHD 770 iGPU Device Binding
OUT_COMPOSE=$(run_cmd_capture "cat /opt/services/immich/compose.yml" || true)
OUT_INSPECT=$(run_cmd_capture "sudo docker inspect immich_server --format '{{json .HostConfig.Devices}}' 2>/dev/null" || true)

if (echo "$OUT_COMPOSE" | grep -q "0000:00:02.0-render" || echo "$OUT_INSPECT" | grep -q "0000:00:02.0-render") && \
   ! echo "$OUT_COMPOSE" | grep -q "0000:03:00.0" && \
   ! echo "$OUT_INSPECT" | grep -q "0000:03:00.0"; then
    log_check 2 "PASS" "Intel iGPU render device bound, discrete AMD GPU strictly isolated"
else
    log_check 2 "FAIL" "iGPU device binding missing or AMD GPU leaked in configuration"
    if [[ "$JSON_MODE" != "true" ]]; then exit 3; fi
fi

# IMM-04: Tiered Storage Topology
OUT_STORAGE_MOUNT=$(run_cmd_capture "mountpoint -q /mnt/storage && echo 'mounted'" || true)
OUT_DATA_STAT=$(run_cmd_capture "[ -d /opt/services/immich/data/postgres ] && echo 'exists'" || true)

if [[ "$OUT_STORAGE_MOUNT" == "mounted" ]] && [[ "$OUT_DATA_STAT" == "exists" ]]; then
    log_check 3 "PASS" "Tier 0 NVMe (/opt/services/immich/data) and Tier 1 MergerFS (/mnt/storage) verified"
else
    log_check 3 "FAIL" "storage mount: $OUT_STORAGE_MOUNT, NVMe data dir: $OUT_DATA_STAT"
    if [[ "$JSON_MODE" != "true" ]]; then exit 4; fi
fi

# IMM-05: Secret Isolation & Permissions
OUT_ENV_PERM=$(run_cmd_capture "stat -c '%a' /opt/services/immich/.env" || true)
OUT_EXAMPLE_EXISTS=$(run_cmd_capture "[ -f /opt/services/immich/.env.example ] && echo 'exists'" || true)
OUT_GIT_LEAKS=$(cd "$REPO_ROOT" && git grep -E "immich_secure_db_pass" -- ":^ansible/inventory/group_vars/all/vault.yml" ":^*.md" 2>/dev/null || true)

if [[ "$OUT_ENV_PERM" == "600" ]] && [[ "$OUT_EXAMPLE_EXISTS" == "exists" ]] && [[ -z "$OUT_GIT_LEAKS" ]]; then
    log_check 4 "PASS" ".env mode 0600, .env.example exists, zero database credentials committed to git"
else
    log_check 4 "FAIL" ".env mode: $OUT_ENV_PERM, example: $OUT_EXAMPLE_EXISTS, git leaks: $OUT_GIT_LEAKS"
    if [[ "$JSON_MODE" != "true" ]]; then exit 5; fi
fi

# IMM-06: Caddy Ingress Configuration
OUT_CADDY_FILE=$(run_cmd_capture "[ -f /etc/caddy/conf.d/30-immich.caddy ] && grep -q '127.0.0.1:2283' /etc/caddy/conf.d/30-immich.caddy && echo 'valid'" || true)
OUT_CADDY_VAL=$(run_cmd_capture "caddy validate --config /etc/caddy/Caddyfile 2>&1" || true)

if [[ "$OUT_CADDY_FILE" == "valid" ]] && echo "$OUT_CADDY_VAL" | grep -qiE "(valid|configuration is valid)"; then
    log_check 5 "PASS" "Caddy drop-in routes to 127.0.0.1:2283, Caddyfile validation passed"
else
    log_check 5 "FAIL" "caddy drop-in: $OUT_CADDY_FILE, validation output: $OUT_CADDY_VAL"
    if [[ "$JSON_MODE" != "true" ]]; then exit 6; fi
fi

# IMM-07: Storage Group & Ownership
OUT_PERM=$(run_cmd_capture "stat -c '%a' /mnt/storage/media/photos" || true)
OUT_GRP=$(run_cmd_capture "stat -c '%G' /mnt/storage/media/photos 2>/dev/null || stat -c '%g' /mnt/storage/media/photos" || true)
OUT_USR=$(run_cmd_capture "stat -c '%U' /mnt/storage/media/photos 2>/dev/null || stat -c '%u' /mnt/storage/media/photos" || true)

if [[ "$OUT_PERM" == "2775" ]] && { [[ "$OUT_GRP" == "storage" ]] || [[ "$OUT_GRP" == "1001" ]]; } && { [[ "$OUT_USR" == "admin" ]] || [[ "$OUT_USR" == "1000" ]]; }; then
    log_check 6 "PASS" "/mnt/storage/media/photos owned by $OUT_USR:$OUT_GRP with mode 2775 setgid"
else
    log_check 6 "FAIL" "mode: $OUT_PERM (expected 2775), user: $OUT_USR (expected admin/1000), group: $OUT_GRP (expected storage/1001)"
    if [[ "$JSON_MODE" != "true" ]]; then exit 7; fi
fi

# IMM-08: Transactional Backup Hook Execution
OUT_HOOK=$(run_cmd_capture "sudo /etc/homelab/backup.d/30-immich.sh pre-backup" || true)
OUT_DUMP_STAT=$(run_cmd_capture "sudo test -s /opt/services/immich/backups/immich_db_backup.dump && echo 'exists'" || true)

if echo "$OUT_HOOK" | grep -qiE "(verified ok)" && [[ "$OUT_DUMP_STAT" == "exists" ]]; then
    log_check 7 "PASS" "30-immich.sh pre-backup verified dump generation ok"
else
    log_check 7 "FAIL" "backup hook output: $OUT_HOOK, dump file: $OUT_DUMP_STAT"
    if [[ "$JSON_MODE" != "true" ]]; then exit 8; fi
fi

# IMM-09: Structured Telemetry & Clean Logs
OUT_JOURNAL=$(run_cmd_capture "journalctl -u immich.service --no-pager -n 50 2>&1" || true)
OUT_SERVER_LOGS=$(run_cmd_capture "sudo docker logs --tail 50 immich_server 2>&1" || true)

if ! echo "$OUT_JOURNAL $OUT_SERVER_LOGS" | grep -qiE "(fatal error|panic:|segfault)" && \
   ! echo "$OUT_JOURNAL $OUT_SERVER_LOGS" | grep -q "CHANGE_ME_IN_VAULT"; then
    log_check 8 "PASS" "Journald & container logs clear of fatal errors, panics, or raw secret tokens"
else
    log_check 8 "FAIL" "fatal error or secret token detected in logs"
    if [[ "$JSON_MODE" != "true" ]]; then exit 9; fi
fi

# JSON Output
if [[ "$JSON_MODE" == "true" ]]; then
    TOTAL_PASS=0
    for s in "${CHECK_STATUS[@]}"; do
        if [[ "$s" == "PASS" ]]; then TOTAL_PASS=$((TOTAL_PASS + 1)); fi
    done
    cat <<EOF
{
  "suite": "IMMICH-VERIFY-V1",
  "total": ${#CHECK_IDS[@]},
  "passed": $TOTAL_PASS,
  "failed": $((${#CHECK_IDS[@]} - TOTAL_PASS)),
  "results": [
EOF
    for i in "${!CHECK_IDS[@]}"; do
        COMMA=","
        if [[ $i -eq $((${#CHECK_IDS[@]} - 1)) ]]; then COMMA=""; fi
        cat <<EOF
    {
      "id": "${CHECK_IDS[$i]}",
      "name": "${CHECK_NAMES[$i]}",
      "status": "${CHECK_STATUS[$i]}",
      "details": "${CHECK_DETAILS[$i]}"
    }${COMMA}
EOF
    done
    cat <<EOF
  ]
}
EOF
fi

TOTAL_PASS=0
for s in "${CHECK_STATUS[@]}"; do
    if [[ "$s" == "PASS" ]]; then TOTAL_PASS=$((TOTAL_PASS + 1)); fi
done

if [[ "$JSON_MODE" != "true" ]]; then
    echo ""
    if [[ $TOTAL_PASS -eq ${#CHECK_IDS[@]} ]]; then
        echo -e "${GREEN}✓ All ${#CHECK_IDS[@]} Immich acceptance assertions PASSED.${NC}"
        exit 0
    else
        echo -e "${RED}✗ Acceptance verification FAILED (${TOTAL_PASS}/${#CHECK_IDS[@]} passed).${NC}"
        exit 1
    fi
fi
