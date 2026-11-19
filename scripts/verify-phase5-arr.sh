#!/usr/bin/env bash
# scripts/verify-phase5-arr.sh
# Acceptance verification runner for homelab2 Phase 5 Media & Arr Stack (Stage 1)
# Enforces the 10-point Assertion Matrix (ARR-01 through ARR-10) from contracts/verification-contract.md:
# ARR-01: arr.service active & 3 containers (arr_vpn, arr_qbittorrent, arr_jellyfin) running healthy (exit 1)
# ARR-02: arr_vpn exit-node tunnel online, external VPN IP != host WAN IP, UID 1000 kill-switch active (exit 2)
# ARR-03: arr_qbittorrent network namespace isolated inside arr_vpn (container:<arr_vpn_id>) (exit 3)
# ARR-04: Jellyfin /health (HTTP 200) & qBittorrent WebUI (HTTP 200) responding on loopback (exit 4)
# ARR-05: WebUI ports bound strictly to 127.0.0.1 & Caddy 40-arr.caddy validated (exit 5)
# ARR-06: Intel UHD 770 iGPU (00:02.0) bound with LIBVA_DRIVER_NAME=iHD; AMD GPU (03:00.0) isolated (exit 6)
# ARR-07: Three-tier storage layout (Stage 1+2 scaffold, scratch, MergerFS) & SnapRAID /downloads/ exclusion (exit 7)
# ARR-08: Unified non-root ownership (PUID=1000, PGID=1001, UMASK=002, mode 2775) verified (exit 8)
# ARR-09: Secret isolation (.env 0600, 0 git leaks) & 40-arr.sh SQLite backup hook verified (exit 9)
# ARR-10: Structured journald & container logs clean with zero fatal panics or credential leaks (exit 10)

set -euo pipefail

TARGET_HOST="192.168.4.57"
SSH_USER="admin"
IDENTITY_FILE=""
LOCAL_MODE=false
JSON_MODE=false
VERBOSE=false

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] [TARGET_HOST]

Options:
  -h, --host <IP|HOSTNAME>   Target host to verify (default: $TARGET_HOST)
  -u, --user <USERNAME>      SSH user for connection (default: $SSH_USER)
  -i, --identity <KEY_PATH>  SSH identity file (private key)
  --local                    Run assertions directly against localhost
  --json                     Output test results in structured JSON format
  --verbose                  Enable verbose diagnostic output
  --help                     Show this help message and exit

Exit Codes:
  0     - All 10 assertions passed (100% compliance)
  1-10  - Specific assertion failure for ARR-01 through ARR-10
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

debug_log() {
    if [[ "$VERBOSE" == "true" ]] && [[ "$JSON_MODE" != "true" ]]; then
        echo "DEBUG: $*" >&2
    fi
}

run_cmd_capture() {
    local cmd="$1"
    debug_log "Executing: $cmd"
    if [[ "$LOCAL_MODE" == "true" ]]; then
        bash -c "$cmd" 2>&1
    else
        local ssh_cmd=(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=30)
        if [[ -n "$IDENTITY_FILE" ]]; then
            ssh_cmd+=(-i "$IDENTITY_FILE")
        fi
        "${ssh_cmd[@]}" "${SSH_USER}@${TARGET_HOST}" "$cmd" 2>&1
    fi
}

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/ }"
    s="${s//$'\r'/ }"
    printf '%s' "$s"
}

CHECK_IDS=("ARR-01" "ARR-02" "ARR-03" "ARR-04" "ARR-05" "ARR-06" "ARR-07" "ARR-08" "ARR-09" "ARR-10")
CHECK_NAMES=(
    "Service & Containers Active"
    "VPN Exit-Node Tunnel & Kill-Switch IP Isolation"
    "qBittorrent Network Namespace Isolation"
    "Jellyfin /health & qBittorrent WebUI Probes"
    "Loopback Binding & Internal Caddy Ingress"
    "Intel UHD 770 iGPU Hardware Acceleration & AMD Isolation"
    "Three-Tier Storage Layout & SnapRAID Exclusion"
    "Unified Non-Root Ownership & Permissions"
    "Secret Isolation & Pre-Backup Hook Readiness"
    "Structured Telemetry & Redacted Logs"
)
CHECK_STATUS=("FAIL" "FAIL" "FAIL" "FAIL" "FAIL" "FAIL" "FAIL" "FAIL" "FAIL" "FAIL")
CHECK_DETAILS=("" "" "" "" "" "" "" "" "" "")

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
    echo -e "${BLUE}=== homelab2 Phase 5 Media & Arr Stage 1 Verification Suite ===${NC}"
    if [[ "$LOCAL_MODE" == "true" ]]; then
        echo "Execution Target: localhost (local execution)"
    else
        echo "Execution Target: ${SSH_USER}@${TARGET_HOST}"
    fi
    echo ""
fi

# ARR-01: Service & Containers Active
OUT_SVC=$(run_cmd_capture "systemctl is-active arr.service" || true)
OUT_CONTAINERS=$(run_cmd_capture "sudo docker ps --filter 'name=arr_' --format '{{.Names}}:{{.Status}}' 2>/dev/null" || true)
CONTAINER_COUNT=$(echo "$OUT_CONTAINERS" | grep -cE "^(arr_vpn|arr_qbittorrent|arr_jellyfin):" || true)

if [[ "$OUT_SVC" =~ "active" ]] && [[ "$CONTAINER_COUNT" -ge 3 ]] && ! echo "$OUT_CONTAINERS" | grep -qi "restarting"; then
    log_check 0 "PASS" "arr.service active, 3 containers (arr_vpn, arr_qbittorrent, arr_jellyfin) operational without restarts"
else
    log_check 0 "FAIL" "service: $OUT_SVC, active containers: $CONTAINER_COUNT/3"
    if [[ "$JSON_MODE" != "true" ]]; then exit 1; fi
fi

# ARR-02: VPN Exit-Node Tunnel & Kill-Switch IP Isolation
VPN_MODE=$(run_cmd_capture "sudo grep -E '^ARR_VPN_MODE=' /opt/services/arr/.env 2>/dev/null | cut -d= -f2" || true)
VPN_MODE="${VPN_MODE:-tailscale}"
HOST_WAN_IP=$(run_cmd_capture "curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null" || true)
VPN_EXT_IP=$(run_cmd_capture "sudo docker exec -u 1000:1001 arr_qbittorrent curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null || sudo docker exec -u 1000:1001 arr_qbittorrent curl -fsS --max-time 8 https://ifconfig.me 2>/dev/null" || true)
IPV4_REGEX='^[0-9]{1,3}(\.[0-9]{1,3}){3}$'

if [[ "$VPN_MODE" == "gluetun" ]]; then
    VPN_HEALTH=$(run_cmd_capture "sudo docker inspect arr_vpn --format '{{.State.Health.Status}}' 2>/dev/null" || true)
    if [[ "$VPN_HEALTH" == "healthy" ]] && [[ "$VPN_EXT_IP" =~ $IPV4_REGEX ]] && [[ -n "$HOST_WAN_IP" ]] && [[ "$VPN_EXT_IP" != "$HOST_WAN_IP" ]]; then
        log_check 1 "PASS" "gluetun healthy, VPN external IP ($VPN_EXT_IP) differs from host WAN IP ($HOST_WAN_IP)"
    else
        log_check 1 "FAIL" "gluetun health: $VPN_HEALTH, VPN IP: $VPN_EXT_IP, host WAN IP: $HOST_WAN_IP"
        if [[ "$JSON_MODE" != "true" ]]; then exit 2; fi
    fi
else
    TS_STATUS=$(run_cmd_capture "sudo docker exec arr_vpn tailscale status --json 2>/dev/null" || true)
    KS_ACTIVE=$(run_cmd_capture "sudo docker exec arr_vpn iptables -C OUTPUT -o eth0 -m owner --uid-owner 1000 -j DROP 2>/dev/null && echo 'active'" || true)
    if echo "$TS_STATUS" | tr -d '\n\r ' | grep -q '"BackendState":"Running"' && \
       echo "$TS_STATUS" | tr -d '\n\r ' | grep -qE '"ExitNodeStatus":\{[^}]*"Online":true' && \
       [[ "$KS_ACTIVE" == "active" ]] && \
       [[ "$VPN_EXT_IP" =~ $IPV4_REGEX ]] && \
       [[ -n "$HOST_WAN_IP" ]] && \
       [[ "$VPN_EXT_IP" != "$HOST_WAN_IP" ]]; then
        log_check 1 "PASS" "Tailscale exit node online, UID 1000 eth0 DROP kill-switch active, VPN IP ($VPN_EXT_IP) != host WAN IP ($HOST_WAN_IP)"
    else
        log_check 1 "FAIL" "kill-switch: ${KS_ACTIVE:-inactive}, VPN IP: ${VPN_EXT_IP:-none}, host WAN IP: ${HOST_WAN_IP:-none}"
        if [[ "$JSON_MODE" != "true" ]]; then exit 2; fi
    fi
fi

# ARR-03: qBittorrent Network Namespace Isolation
VPN_ID=$(run_cmd_capture "sudo docker inspect arr_vpn --format '{{.Id}}' 2>/dev/null" || true)
QBIT_NETMODE=$(run_cmd_capture "sudo docker inspect arr_qbittorrent --format '{{.HostConfig.NetworkMode}}' 2>/dev/null" || true)
QBIT_NETWORKS=$(run_cmd_capture "sudo docker inspect arr_qbittorrent --format '{{json .NetworkSettings.Networks}}' 2>/dev/null" || true)

if [[ -n "$VPN_ID" ]] && [[ "$QBIT_NETMODE" == "container:${VPN_ID}" ]] && { [[ "$QBIT_NETWORKS" == "{}" ]] || [[ "$QBIT_NETWORKS" == "null" ]]; }; then
    log_check 2 "PASS" "arr_qbittorrent isolated inside container:${VPN_ID:0:12} with empty Networks map"
else
    log_check 2 "FAIL" "NetworkMode: '$QBIT_NETMODE' (expected container:$VPN_ID), Networks: $QBIT_NETWORKS"
    if [[ "$JSON_MODE" != "true" ]]; then exit 3; fi
fi

# ARR-04: Jellyfin /health & qBittorrent WebUI Probes
START_TIME=$(date +%s%N)
JF_HEALTH=$(run_cmd_capture "curl -fsS --max-time 2 http://127.0.0.1:8096/health" || true)
QBIT_CODE=$(run_cmd_capture "curl -fsS --max-time 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:8080" || true)
END_TIME=$(date +%s%N)
ELAPSED_MS=$(( (END_TIME - START_TIME) / 1000000 ))

if [[ "$JF_HEALTH" == *"Healthy"* ]] && [[ "$QBIT_CODE" == "200" ]]; then
    log_check 3 "PASS" "Jellyfin /health HTTP 200 (Healthy) & qBittorrent WebUI HTTP 200 in ${ELAPSED_MS}ms"
else
    log_check 3 "FAIL" "Jellyfin health: '$JF_HEALTH', qBittorrent HTTP status: '$QBIT_CODE' (${ELAPSED_MS}ms)"
    if [[ "$JSON_MODE" != "true" ]]; then exit 4; fi
fi

# ARR-05: Loopback Binding & Internal Caddy Ingress
PORTS_VPN=$(run_cmd_capture "sudo docker port arr_vpn 2>/dev/null" || true)
PORTS_JF=$(run_cmd_capture "sudo docker port arr_jellyfin 2>/dev/null" || true)
CADDY_CHECK=$(run_cmd_capture "[ -f /etc/caddy/conf.d/40-arr.caddy ] && grep -q '@internal' /etc/caddy/conf.d/40-arr.caddy && grep -q '127.0.0.1:8096' /etc/caddy/conf.d/40-arr.caddy && grep -q '127.0.0.1:8080' /etc/caddy/conf.d/40-arr.caddy && echo 'valid'" || true)
CADDY_VAL=$(run_cmd_capture "caddy validate --config /etc/caddy/Caddyfile 2>&1" || true)

if echo "$PORTS_VPN" | grep -q "127.0.0.1:8080" && \
   echo "$PORTS_JF" | grep -q "127.0.0.1:8096" && \
   ! echo "$PORTS_VPN $PORTS_JF" | grep -qE "(0\.0\.0\.0:|\[::\]:)" && \
   [[ "$CADDY_CHECK" == "valid" ]] && \
   echo "$CADDY_VAL" | grep -qiE "(valid|configuration is valid)"; then
    log_check 4 "PASS" "Loopback ports 127.0.0.1:{8096,8080} verified and 40-arr.caddy validated"
else
    log_check 4 "FAIL" "ports_vpn: '$PORTS_VPN', ports_jf: '$PORTS_JF', caddy_check: '$CADDY_CHECK'"
    if [[ "$JSON_MODE" != "true" ]]; then exit 5; fi
fi

# ARR-06: Intel UHD 770 iGPU Hardware Acceleration & AMD Isolation
OUT_COMPOSE=$(run_cmd_capture "cat /opt/services/arr/compose.yml" || true)
JF_DEVICES=$(run_cmd_capture "sudo docker inspect arr_jellyfin --format '{{json .HostConfig.Devices}}' 2>/dev/null" || true)
JF_ENV=$(run_cmd_capture "sudo docker inspect arr_jellyfin --format '{{json .Config.Env}}' 2>/dev/null" || true)

if echo "$OUT_COMPOSE" | grep -q "0000:00:02.0-render" && \
   echo "$JF_DEVICES" | grep -q "0000:00:02.0-render" && \
   echo "$JF_ENV" | grep -q "LIBVA_DRIVER_NAME=iHD" && \
   ! echo "$OUT_COMPOSE $JF_DEVICES" | grep -q "03:00.0"; then
    log_check 5 "PASS" "Intel UHD 770 iGPU (00:02.0-render) & LIBVA_DRIVER_NAME=iHD bound; discrete AMD GPU isolated"
else
    log_check 5 "FAIL" "iGPU device or LIBVA_DRIVER_NAME=iHD missing, or AMD GPU referenced"
    if [[ "$JSON_MODE" != "true" ]]; then exit 6; fi
fi

# ARR-07: Three-Tier Storage Layout & SnapRAID Exclusion
SCAFFOLD_OK=$(run_cmd_capture "for d in vpn gluetun qbittorrent jellyfin ersatztv jellyseerr prowlarr radarr sonarr; do [ -d \"/opt/services/arr/\$d/config\" ] || exit 1; done; mountpoint -q /mnt/scratch && [ -d /mnt/scratch/downloads/incomplete ] && mountpoint -q /mnt/storage && [ -d /mnt/storage/downloads/complete ] && [ -d /mnt/storage/media/movies ] && [ -d /mnt/storage/media/tv ] && echo 'ok'" || true)
DEV_IDS=$(run_cmd_capture "stat -c '%d' /mnt/storage/downloads/complete /mnt/storage/media/movies /mnt/storage/media/tv 2>/dev/null | sort -u | wc -l" || true)
SNAPRAID_EXCL=$(run_cmd_capture "grep -qE '^exclude[[:space:]]+/downloads/' /etc/snapraid.conf && echo 'ok'" || true)

if [[ "$SCAFFOLD_OK" == "ok" ]] && [[ "$DEV_IDS" == "1" ]] && [[ "$SNAPRAID_EXCL" == "ok" ]]; then
    log_check 6 "PASS" "Three-tier storage layout (Stage 1+2 scaffold), single MergerFS st_dev, and SnapRAID /downloads/ exclusion verified"
else
    log_check 6 "FAIL" "scaffold: '$SCAFFOLD_OK', distinct st_dev count: '$DEV_IDS', snapraid exclude: '$SNAPRAID_EXCL'"
    if [[ "$JSON_MODE" != "true" ]]; then exit 7; fi
fi

# ARR-08: Unified Non-Root Ownership & Permissions
ENV_IDS=$(run_cmd_capture "sudo grep -E '^(PUID=1000|PGID=1001|UMASK=002)$' /opt/services/arr/.env 2>/dev/null | wc -l" || true)
PERMS_OK=$(run_cmd_capture "for d in /mnt/scratch/downloads/incomplete /mnt/storage/downloads/complete /mnt/storage/media/movies /mnt/storage/media/tv; do [ \"\$(stat -c '%a %u:%g' \"\$d\")\" = '2775 1000:1001' ] || exit 1; done; echo 'ok'" || true)

if [[ "$ENV_IDS" -ge 3 ]] && [[ "$PERMS_OK" == "ok" ]]; then
    log_check 7 "PASS" "PUID=1000, PGID=1001, UMASK=002 and mode 2775 (1000:1001) verified across scratch and MergerFS"
else
    log_check 7 "FAIL" "env id matches: '$ENV_IDS'/3, directory perms: '$PERMS_OK'"
    if [[ "$JSON_MODE" != "true" ]]; then exit 8; fi
fi

# ARR-09: Secret Isolation & Pre-Backup Hook Readiness
ENV_MODE=$(run_cmd_capture "sudo stat -c '%a' /opt/services/arr/.env 2>/dev/null" || true)
EXAMPLE_OK=$(run_cmd_capture "[ -f /opt/services/arr/.env.example ] && echo 'exists'" || true)
GIT_LEAKS=$(cd "$REPO_ROOT" && git grep -E "tskey-auth-[A-Za-z0-9]{10,}" -- ":^*.md" ":^*.example" ":^scripts/verify-phase5-arr.*" ":^ansible/playbooks/verify-phase5-arr.yml" 2>/dev/null || true)
RESTIC_EXCL=$(run_cmd_capture "grep -q '/mnt/storage/downloads/\*\*' /etc/homelab/backup-excludes.txt && grep -q '/mnt/storage/media/movies/\*\*' /etc/homelab/backup-excludes.txt && echo 'ok'" || true)
BACKUP_HOOK_OUT=$(run_cmd_capture "sudo /etc/homelab/backup.d/40-arr.sh pre-backup" || true)
BACKUP_ARCHIVE=$(run_cmd_capture "sudo test -s /opt/services/arr/backups/arr-configs-snapshot.tar.gz && echo 'exists'" || true)

if [[ "$ENV_MODE" == "600" ]] && [[ "$EXAMPLE_OK" == "exists" ]] && [[ -z "$GIT_LEAKS" ]] && [[ "$RESTIC_EXCL" == "ok" ]] && echo "$BACKUP_HOOK_OUT" | grep -qi "verified ok" && [[ "$BACKUP_ARCHIVE" == "exists" ]]; then
    log_check 8 "PASS" ".env mode 0600, 0 git leaks, Restic exclusions active, and 40-arr.sh pre-backup verified ok"
else
    log_check 8 "FAIL" ".env mode: '$ENV_MODE', example: '$EXAMPLE_OK', restic_excl: '$RESTIC_EXCL', archive: '$BACKUP_ARCHIVE'"
    if [[ "$JSON_MODE" != "true" ]]; then exit 9; fi
fi

# ARR-10: Structured Telemetry & Redacted Logs
OUT_JOURNAL=$(run_cmd_capture "journalctl -u arr.service --no-pager -n 50 2>&1" || true)
OUT_LOGS=$(run_cmd_capture "sudo docker logs --tail 50 arr_vpn 2>&1; sudo docker logs --tail 50 arr_qbittorrent 2>&1; sudo docker logs --tail 50 arr_jellyfin 2>&1" || true)

if ! echo "$OUT_JOURNAL $OUT_LOGS" | grep -qiE "(fatal error|panic:|segfault)" && \
   ! echo "$OUT_JOURNAL $OUT_LOGS" | grep -qE "tskey-auth-[A-Za-z0-9]+"; then
    log_check 9 "PASS" "Journald & container logs clean with zero fatal panics or leaked credentials"
else
    log_check 9 "FAIL" "fatal error or unredacted credential detected in logs"
    if [[ "$JSON_MODE" != "true" ]]; then exit 10; fi
fi

TOTAL_PASS=0
for s in "${CHECK_STATUS[@]}"; do
    if [[ "$s" == "PASS" ]]; then TOTAL_PASS=$((TOTAL_PASS + 1)); fi
done

if [[ "$JSON_MODE" == "true" ]]; then
    cat <<EOF
{
  "suite": "ARR-VERIFY-V1",
  "total": ${#CHECK_IDS[@]},
  "passed": $TOTAL_PASS,
  "failed": $((${#CHECK_IDS[@]} - TOTAL_PASS)),
  "results": [
EOF
    for i in "${!CHECK_IDS[@]}"; do
        COMMA=","
        if [[ $i -eq $((${#CHECK_IDS[@]} - 1)) ]]; then COMMA=""; fi
        ESC_DETAILS=$(json_escape "${CHECK_DETAILS[$i]}")
        cat <<EOF
    {
      "id": "${CHECK_IDS[$i]}",
      "name": "${CHECK_NAMES[$i]}",
      "status": "${CHECK_STATUS[$i]}",
      "details": "${ESC_DETAILS}"
    }${COMMA}
EOF
    done
    cat <<EOF
  ]
}
EOF
    if [[ $TOTAL_PASS -eq ${#CHECK_IDS[@]} ]]; then exit 0; else exit 1; fi
fi

echo ""
if [[ $TOTAL_PASS -eq ${#CHECK_IDS[@]} ]]; then
    echo -e "${GREEN}✓ All ${#CHECK_IDS[@]} Media & Arr Stage 1 acceptance assertions PASSED.${NC}"
    exit 0
else
    echo -e "${RED}✗ Acceptance verification FAILED (${TOTAL_PASS}/${#CHECK_IDS[@]} passed).${NC}"
    exit 1
fi
