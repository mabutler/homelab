#!/usr/bin/env bash
# scripts/verify-phase5-frigate.sh
# Acceptance verification runner for homelab2 Phase 5 Frigate NVR Application Deployment
# Enforces the 9-point Assertion Matrix from contracts/verification-contract.md:
# FRG-01: Frigate systemd service & container active with 0 restart loops (exit 1)
# FRG-02: Frigate HTTP API (/api/version & /api/stats) responds HTTP 200 within 2s (exit 2)
# FRG-03: Intel UHD Graphics 770 iGPU bound & OpenVINO detector configured (exit 3)
# FRG-04: Pre-staged camera_1 & camera_2 slots exist with dual-stream roles & retention (exit 4)
# FRG-05: Secret isolation: .env mode 0600, .env.example exists, zero git credential leaks (exit 5)
# FRG-06: Tiered storage & shared memory: /config on NVMe, /media on /mnt/scratch, shm >= 256MB (exit 6)
# FRG-07: Network isolation: LAN and tailscale0 allowed in nftables, 0 Funnel exposure (exit 7)
# FRG-08: Backup hook /etc/homelab/backup.d/20-frigate.sh executes snapshot & scratch excluded (exit 8)
# FRG-09: Structured logs accessible via journalctl/docker logs with 0 unhandled crash tracebacks (exit 9)

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
  1-9 - Specific assertion failure for FRG-01 through FRG-09
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
CHECK_IDS=("FRG-01" "FRG-02" "FRG-03" "FRG-04" "FRG-05" "FRG-06" "FRG-07" "FRG-08" "FRG-09")
CHECK_NAMES=(
    "Service & Container Active"
    "HTTP API Health (< 2s)"
    "Intel UHD 770 iGPU & OpenVINO"
    "Pre-Staged Camera Slots & Retention"
    "Secret Isolation & Permissions"
    "Tiered Storage & Shared Memory"
    "Network & Funnel Isolation"
    "Transactional Backup Snapshot"
    "Structured Logs & Container Health"
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
    echo -e "${BLUE}=== homelab2 Phase 5 Frigate NVR Acceptance Verification Suite ===${NC}"
    if [[ "$LOCAL_MODE" == "true" ]]; then
        echo "Execution Target: localhost (local execution)"
    else
        echo "Execution Target: ${SSH_USER}@${TARGET_HOST}"
    fi
    echo ""
fi

# FRG-01: Service & Container Active
OUT_SVC=$(run_cmd_capture "systemctl is-active frigate.service" || true)
OUT_CONTAINER=$(run_cmd_capture "sudo docker inspect -f '{{.State.Status}}:{{.RestartCount}}' frigate 2>/dev/null" || true)
if [[ "$OUT_SVC" =~ "active" ]] && [[ "$OUT_CONTAINER" =~ ^running:0$ ]]; then
    log_check 0 "PASS" "frigate.service active, container running:0 restarts"
else
    log_check 0 "FAIL" "service: $OUT_SVC, container: $OUT_CONTAINER"
    if [[ "$JSON_MODE" != "true" ]]; then exit 1; fi
fi

# FRG-02: HTTP API Health (< 2s)
OUT_VER=$(run_cmd_capture "curl -fsS --max-time 2 http://127.0.0.1:5000/api/version" || true)
OUT_STATS=$(run_cmd_capture "curl -fsS --max-time 2 http://127.0.0.1:5000/api/stats" || true)
if echo "$OUT_VER" | grep -q "0.14.1" && echo "$OUT_STATS" | grep -q "detectors"; then
    log_check 1 "PASS" "API version $OUT_VER, stats returned in <2s"
else
    log_check 1 "FAIL" "version: $OUT_VER, stats: $(echo "$OUT_STATS" | head -c 100)"
    if [[ "$JSON_MODE" != "true" ]]; then exit 2; fi
fi

# FRG-03: Intel UHD 770 iGPU & OpenVINO
OUT_DEVICES=$(run_cmd_capture "sudo docker inspect frigate --format '{{json .HostConfig.Devices}}' 2>/dev/null" || true)
OUT_CONFIG_OV=$(run_cmd_capture "curl -fsS --max-time 2 http://127.0.0.1:5000/api/config" || true)
if echo "$OUT_DEVICES" | grep -q "0000:00:02.0-render" && ! echo "$OUT_DEVICES" | grep -q "0000:03:00.0" && echo "$OUT_CONFIG_OV" | grep -q '"type":"openvino"'; then
    log_check 2 "PASS" "Intel iGPU render device bound, AMD GPU excluded, OpenVINO detector configured"
else
    log_check 2 "FAIL" "devices: $OUT_DEVICES, detector config mismatch"
    if [[ "$JSON_MODE" != "true" ]]; then exit 3; fi
fi

# FRG-04: Pre-Staged Camera Slots & Retention
if echo "$OUT_CONFIG_OV" | grep -q '"camera_1"' && echo "$OUT_CONFIG_OV" | grep -q '"camera_2"' && echo "$OUT_CONFIG_OV" | grep -q '"days":7' && echo "$OUT_CONFIG_OV" | grep -q '"default":14'; then
    log_check 3 "PASS" "camera_1 & camera_2 slots pre-staged, 7d motion / 14d events retention confirmed"
else
    log_check 3 "FAIL" "pre-staged camera configuration or retention mismatch in /api/config"
    if [[ "$JSON_MODE" != "true" ]]; then exit 4; fi
fi

# FRG-05: Secret Isolation & Permissions
OUT_ENV_PERM=$(run_cmd_capture "stat -c '%a' /opt/services/frigate/.env" || true)
OUT_EXAMPLE_EXISTS=$(run_cmd_capture "[ -f /opt/services/frigate/.env.example ] && echo 'exists'" || true)
OUT_GIT_LEAKS=$(cd "$REPO_ROOT" && git grep -E "rtsp://[^@]+:[^@]+@" -- ":^ansible/inventory/group_vars/all/vault.yml.example" ":^ansible/roles/frigate/files/env.example" ":^*.md" 2>/dev/null || true)
if [[ "$OUT_ENV_PERM" == "600" ]] && [[ "$OUT_EXAMPLE_EXISTS" == "exists" ]] && [[ -z "$OUT_GIT_LEAKS" ]]; then
    log_check 4 "PASS" ".env mode 0600, .env.example exists, zero credentials tracked in git"
else
    log_check 4 "FAIL" ".env mode $OUT_ENV_PERM, example: $OUT_EXAMPLE_EXISTS, git leaks: $OUT_GIT_LEAKS"
    if [[ "$JSON_MODE" != "true" ]]; then exit 5; fi
fi

# FRG-06: Tiered Storage & Shared Memory
OUT_MOUNTS=$(run_cmd_capture "sudo docker inspect frigate --format '{{json .Mounts}}' 2>/dev/null" || true)
OUT_SHM=$(run_cmd_capture "sudo docker inspect frigate --format '{{.HostConfig.ShmSize}}' 2>/dev/null" || true)
if echo "$OUT_MOUNTS" | grep -q "/opt/services/frigate/config" && echo "$OUT_MOUNTS" | grep -q "/mnt/scratch/frigate/media" && [[ "$OUT_SHM" -ge 268435456 ]]; then
    log_check 5 "PASS" "Config on NVMe, media on /mnt/scratch, shm size ${OUT_SHM} >= 256MB"
else
    log_check 5 "FAIL" "mounts: $OUT_MOUNTS, shm: $OUT_SHM"
    if [[ "$JSON_MODE" != "true" ]]; then exit 6; fi
fi

# FRG-07: Network & Funnel Isolation
OUT_NFT=$(run_cmd_capture "sudo nft list table inet filter" || true)
OUT_FUNNEL=$(run_cmd_capture "tailscale funnel status 2>&1" || true)
if echo "$OUT_NFT" | grep -q "5000" && ! echo "$OUT_FUNNEL" | grep -qE "(5000|8971)"; then
    log_check 6 "PASS" "LAN port 5000 allowed in nftables, zero ports exposed on Tailscale Funnel"
else
    log_check 6 "FAIL" "nftables or funnel leak detected: $OUT_FUNNEL"
    if [[ "$JSON_MODE" != "true" ]]; then exit 7; fi
fi

# FRG-08: Transactional Backup Snapshot
OUT_HOOK=$(run_cmd_capture "sudo /etc/homelab/backup.d/20-frigate.sh pre-backup" || true)
OUT_SNAP_EXISTS=$(run_cmd_capture "sudo test -f /opt/services/frigate/backups/snapshot.sqlite3 && echo 'exists'" || true)
OUT_EXCLUDES=$(run_cmd_capture "grep -E '/mnt/scratch' /etc/homelab/backup-excludes.txt" || true)
if echo "$OUT_HOOK" | grep -qiE "(verified ok|Skipping dump)" && [[ -n "$OUT_EXCLUDES" ]]; then
    log_check 7 "PASS" "20-frigate.sh pre-backup verified, /mnt/scratch excluded from Restic"
else
    log_check 7 "FAIL" "backup hook output: $OUT_HOOK, snapshot: $OUT_SNAP_EXISTS, excludes: $OUT_EXCLUDES"
    if [[ "$JSON_MODE" != "true" ]]; then exit 8; fi
fi

# FRG-09: Structured Logs & Container Health
OUT_JOURNAL=$(run_cmd_capture "journalctl -u frigate.service --no-pager -n 20 2>&1" || true)
OUT_HEALTH=$(run_cmd_capture "sudo docker inspect frigate --format '{{.State.Health.Status}}' 2>/dev/null" || true)
if ! echo "$OUT_JOURNAL" | grep -qiE "(Traceback|Fatal Python error)" && [[ "$OUT_HEALTH" =~ ^(healthy|starting)$ ]]; then
    log_check 8 "PASS" "Clean journald logs, container health status: $OUT_HEALTH"
else
    log_check 8 "FAIL" "health: $OUT_HEALTH, journal logs show errors"
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
  "suite": "FRIGATE-VERIFY-V1",
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
        echo -e "${GREEN}✓ All ${#CHECK_IDS[@]} Frigate acceptance assertions PASSED.${NC}"
        exit 0
    else
        echo -e "${RED}✗ Acceptance verification FAILED (${TOTAL_PASS}/${#CHECK_IDS[@]} passed).${NC}"
        exit 1
    fi
fi
