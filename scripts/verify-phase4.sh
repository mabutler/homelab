#!/usr/bin/env bash
# scripts/verify-phase4.sh
# Acceptance verification runner for homelab2 Phase 4 (Storage Pooling & Data Resiliency Layer)
# Enforces the 10-point Assertion Matrix from contracts/verification-suite.md:
# STO-01: Physical disk mounts active in /proc/mounts and /etc/fstab (exit 1)
# STO-02: MergerFS pool /mnt/storage mounted with fuse.mergerfs (exit 2)
# STO-03: Pool read/write/delete lifecycle on /mnt/storage places file on underlying disk (exit 3)
# STO-04: Scratch tier /mnt/scratch isolated from MergerFS branches (exit 4)
# STO-05: Fast NVMe app tier /opt/services exists with admin:storage (exit 5)
# STO-06: Storage group GID 1001 exists, admin is member, setgid 2775 on /mnt/storage & /mnt/scratch (exit 6)
# STO-07: SnapRAID configuration valid and array healthy via snapraid status (exit 7)
# STO-08: Parity safety runner /usr/local/bin/snapraid-runner.sh executable & functional (exit 8)
# STO-09: Systemd timers snapraid-sync.timer & snapraid-scrub.timer active & enabled (exit 9)
# STO-10: Systemd journal telemetry records structured storage/snapraid events (exit 10)

set -euo pipefail

TARGET_HOST="192.168.4.57"
SSH_USER="admin"
IDENTITY_FILE=""
LOCAL_MODE=false

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] [TARGET_HOST]

Options:
  -h, --host <IP|HOSTNAME>   Target host to verify (default: $TARGET_HOST)
  -u, --user <USERNAME>       SSH user for test connection (default: $SSH_USER)
  -i, --identity <KEY_PATH>   SSH identity file (private key)
  --local                     Run assertions directly against localhost
  --help                      Show this help message and exit

Exit Codes:
  0 - All 10 assertions passed (100% compliance)
  1-10 - Specific assertion failure for STO-01 through STO-10
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

echo -e "${BLUE}=== homelab2 Phase 4 Acceptance Verification Suite ===${NC}"
if [[ "$LOCAL_MODE" == "true" ]]; then
    echo "Execution Target: localhost (local execution)"
else
    echo "Execution Target: ${SSH_USER}@${TARGET_HOST}"
fi
echo ""

# Assertion 1: STO-01 Physical Disk Mounts
echo -n "Checking STO-01: Physical disk mounts active in /proc/mounts and /etc/fstab... "
MOUNTS_OK=true
for mp in "/mnt/disks/data1" "/mnt/disks/data2" "/mnt/disks/parity1" "/mnt/scratch"; do
    if ! run_cmd "grep -qs ' $mp ' /proc/mounts && grep -qs ' $mp ' /etc/fstab"; then
        MOUNTS_OK=false
        break
    fi
done

if [[ "$MOUNTS_OK" == "true" ]]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "ERROR: [STO-01] One or more physical disks not mounted or missing in /etc/fstab" >&2
    exit 1
fi

# Assertion 2: STO-02 MergerFS Pool Mount
echo -n "Checking STO-02: MergerFS virtual pool active at /mnt/storage... "
if run_cmd "grep -qs '^[^ ]* /mnt/storage fuse.mergerfs ' /proc/mounts && mountpoint -q /mnt/storage"; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "ERROR: [STO-02] /mnt/storage is not mounted as fuse.mergerfs" >&2
    exit 2
fi

# Assertion 3: STO-03 Pool Read/Write/Delete
echo -n "Checking STO-03: Pool write, underlying placement, and delete lifecycle... "
TEST_FILE_NAME="test-verify-sto03-$(date +%s%N).tmp"
TEST_WRITE_CMD="TEST_FILE='/mnt/storage/$TEST_FILE_NAME'; echo 'sto03-payload' > \"\$TEST_FILE\" && grep -qs 'sto03-payload' \"\$TEST_FILE\" && [ -n \"\$(find /mnt/disks/data* -maxdepth 2 -name '$TEST_FILE_NAME' 2>/dev/null | head -n1)\" ] && rm -f \"\$TEST_FILE\" && ! test -f \"\$TEST_FILE\""

if run_cmd "$TEST_WRITE_CMD"; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "ERROR: [STO-03] Write, placement, or deletion test failed on /mnt/storage" >&2
    exit 3
fi

# Assertion 4: STO-04 Scratch Tier Isolation
echo -n "Checking STO-04: Scratch tier /mnt/scratch isolated from MergerFS branches... "
FSTAB_MERGERFS=$(run_cmd "grep -E '/mnt/storage' /etc/fstab" 2>/dev/null || true)
if [[ "$FSTAB_MERGERFS" != *"/mnt/scratch"* ]] && run_cmd "mountpoint -q /mnt/scratch"; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "ERROR: [STO-04] /mnt/scratch is included in MergerFS branches or not mounted" >&2
    exit 4
fi

# Assertion 5: STO-05 NVMe App Tier Setup
echo -n "Checking STO-05: NVMe application tier /opt/services exists with proper ownership... "
SERVICES_STAT=$(run_cmd "stat -c '%U:%G:%a' /opt/services" 2>/dev/null || true)
if [[ "$SERVICES_STAT" == "admin:storage:775" || "$SERVICES_STAT" == "admin:storage:755" ]]; then
    echo -e "${GREEN}PASS${NC} (stat: $SERVICES_STAT)"
else
    echo -e "${RED}FAIL${NC} (got $SERVICES_STAT)"
    echo "ERROR: [STO-05] /opt/services does not match admin:storage:775 or 755" >&2
    exit 5
fi

# Assertion 6: STO-06 Storage Group & Setgid
echo -n "Checking STO-06: Storage group GID 1001, admin member, and setgid on /mnt/storage & /mnt/scratch... "
GID_CHECK=$(run_cmd "getent group storage | cut -d: -f3" 2>/dev/null || true)
ADMIN_IN_GROUP=$(run_cmd "id -Gn admin | grep -qw storage && echo true || echo false" 2>/dev/null || true)
STORAGE_MODE=$(run_cmd "stat -c '%a' /mnt/storage" 2>/dev/null || true)
SCRATCH_MODE=$(run_cmd "stat -c '%a' /mnt/scratch" 2>/dev/null || true)

if [[ "$GID_CHECK" == "1001" ]] && [[ "$ADMIN_IN_GROUP" == "true" ]] && [[ "$STORAGE_MODE" == "2775" ]] && [[ "$SCRATCH_MODE" == "2775" ]]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC} (GID: $GID_CHECK, admin_in_storage: $ADMIN_IN_GROUP, storage_mode: $STORAGE_MODE, scratch_mode: $SCRATCH_MODE)"
    echo "ERROR: [STO-06] Storage group configuration or setgid bit mismatch" >&2
    exit 6
fi

# Assertion 7: STO-07 SnapRAID Configuration & Status
echo -n "Checking STO-07: SnapRAID configuration syntax and array status... "
if run_cmd "sudo snapraid status" >/dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "ERROR: [STO-07] snapraid status failed or /etc/snapraid.conf is invalid" >&2
    exit 7
fi

# Assertion 8: STO-08 Parity Safety Runner
echo -n "Checking STO-08: Parity safety runner script exists and is executable... "
if run_cmd "test -x /usr/local/bin/snapraid-runner.sh && sudo /usr/local/bin/snapraid-runner.sh" >/dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "ERROR: [STO-08] /usr/local/bin/snapraid-runner.sh is missing, non-executable, or failed dry-run" >&2
    exit 8
fi

# Assertion 9: STO-09 Systemd Timers Active
echo -n "Checking STO-09: Systemd timers snapraid-sync.timer & snapraid-scrub.timer active & enabled... "
SYNC_ACTIVE=$(run_cmd "systemctl is-active snapraid-sync.timer" 2>/dev/null || true)
SCRUB_ACTIVE=$(run_cmd "systemctl is-active snapraid-scrub.timer" 2>/dev/null || true)
SYNC_ENABLED=$(run_cmd "systemctl is-enabled snapraid-sync.timer" 2>/dev/null || true)
SCRUB_ENABLED=$(run_cmd "systemctl is-enabled snapraid-scrub.timer" 2>/dev/null || true)

if [[ "$SYNC_ACTIVE" == "active" ]] && [[ "$SCRUB_ACTIVE" == "active" ]] && [[ "$SYNC_ENABLED" == "enabled" ]] && [[ "$SCRUB_ENABLED" == "enabled" ]]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC} (sync: $SYNC_ACTIVE/$SYNC_ENABLED, scrub: $SCRUB_ACTIVE/$SCRUB_ENABLED)"
    echo "ERROR: [STO-09] SnapRAID sync or scrub timer not active and enabled" >&2
    exit 9
fi

# Assertion 10: STO-10 Journald Telemetry
echo -n "Checking STO-10: Journald telemetry contains SnapRAID execution events... "
JOURNAL_SNAPRAID=$(run_cmd "journalctl -t snapraid -n 5" 2>/dev/null || true)
if echo "$JOURNAL_SNAPRAID" | grep -Eq "SnapRAID"; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "ERROR: [STO-10] No SnapRAID structured telemetry found in system journal" >&2
    exit 10
fi

echo ""
echo -e "${GREEN}✓ All 10 storage acceptance assertions passed successfully (100% compliance).${NC}"
exit 0
