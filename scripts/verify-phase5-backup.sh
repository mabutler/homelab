#!/usr/bin/env bash
# scripts/verify-phase5-backup.sh - Automated Backup Acceptance Verification
# Complies with BACKUP-VERIFICATION-V1 contract
set -euo pipefail

JSON_MODE=false
for arg in "$@"; do
    if [[ "$arg" == "--json" ]]; then
        JSON_MODE=true
    fi
done

START_TIME=$(date +%s%3N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1000))')
PASSED=0
FAILED=0
ASSERTIONS=()

run_assertion() {
    local id="$1"
    local name="$2"
    local cmd="$3"
    local a_start
    a_start=$(date +%s%3N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1000))')

    local status="PASS"
    local output=""
    if ! output=$(eval "$cmd" 2>&1); then
        status="FAIL"
    fi
    local a_end
    a_end=$(date +%s%3N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1000))')
    local a_dur=$((a_end - a_start))

    if [[ "$status" == "PASS" ]]; then
        PASSED=$((PASSED + 1))
        if [[ "$JSON_MODE" != true ]]; then
            echo -e "[\033[32mPASS\033[0m] $id: $name (${a_dur}ms)"
        fi
    else
        FAILED=$((FAILED + 1))
        if [[ "$JSON_MODE" != true ]]; then
            echo -e "[\033[31mFAIL\033[0m] $id: $name (${a_dur}ms)"
            echo "       Error: $output" >&2
        fi
    fi

    ASSERTIONS+=("{\"id\": \"$id\", \"name\": \"$name\", \"status\": \"$status\", \"duration_ms\": $a_dur}")
}

# BK-001: Restic Binary Installed
run_assertion "BK-001" "Restic Binary Installed" "command -v restic >/dev/null && restic version >/dev/null"

# BK-002: Backup Environment Permissions
run_assertion "BK-002" "Backup Environment Permissions" "[ \"\$(stat -c '%a %U:%G' /etc/homelab/backup.env 2>/dev/null)\" = '600 root:root' ]"

# Source environment for subsequent checks
if [ -f /etc/homelab/backup.env ]; then
    set -a
    # shellcheck disable=SC1091
    source /etc/homelab/backup.env
    set +a
fi

# BK-003: B2 Cloud Repository Connectivity
run_assertion "BK-003" "B2 Cloud Repository Connectivity" "restic -r \"\$RESTIC_REPOSITORY\" snapshots --json >/dev/null"

# BK-004: Secret File Included in Snapshot
run_assertion "BK-004" "Secret File Included in Snapshot" "restic -r \"\$RESTIC_REPOSITORY\" ls latest | grep -E '(^|/)etc/homelab/vault\\.yml' >/dev/null"

# BK-005: Live DB Excluded from Snapshot
run_assertion "BK-005" "Live DB Excluded from Snapshot" "! restic -r \"\$RESTIC_REPOSITORY\" ls latest | grep -E 'db\\.sqlite3\$' >/dev/null"

# BK-006: Pre-Backup Hook & Snapshot Verified
run_assertion "BK-006" "Pre-Backup Hook & Snapshot Verified" "/usr/local/bin/homelab-backup run --dry-run >/dev/null"

# BK-007: Automated Timers Active
run_assertion "BK-007" "Automated Timers Active" "systemctl is-active homelab-backup.timer >/dev/null && systemctl is-active homelab-backup-check.timer >/dev/null"

# BK-008: Non-Destructive Restore Viability
# shellcheck disable=SC2329
test_restore_fn() {
    local target="/tmp/b2-test-restore"
    rm -rf "$target"
    mkdir -p "$target"

    local script_path=""
    for s in /usr/local/bin/restore-from-b2.sh /tmp/restore-from-b2.sh ./scripts/restore-from-b2.sh /opt/homelab2/scripts/restore-from-b2.sh; do
        if [ -x "$s" ] || [ -f "$s" ]; then
            script_path="$s"
            break
        fi
    done

    if [ -z "$script_path" ]; then
        echo "restore-from-b2.sh not found" >&2
        return 1
    fi

    "$script_path" --target-dir "$target" --include-path etc/homelab/vault.yml --force >/dev/null || return 1

    local orig_sum
    orig_sum=$(sha256sum /etc/homelab/vault.yml | awk '{print $1}')
    local rest_sum
    rest_sum=$(sha256sum "$target/etc/homelab/vault.yml" | awk '{print $1}')
    rm -rf "$target"

    [ -n "$orig_sum" ] && [ "$orig_sum" = "$rest_sum" ]
}
run_assertion "BK-008" "Non-Destructive Restore Viability" "test_restore_fn"

END_TIME=$(date +%s%3N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1000))')
TOTAL_DUR=$((END_TIME - START_TIME))
TOTAL=$((PASSED + FAILED))

if [[ "$JSON_MODE" == true ]]; then
    JOINED_ASSERTIONS=$(IFS=,; echo "${ASSERTIONS[*]}")
    cat << EOF
{
  "timestamp": "$(date -Iseconds)",
  "feature": "006-backblaze-backup-restore",
  "target": "homelab2",
  "summary": {
    "total": $TOTAL,
    "passed": $PASSED,
    "failed": $FAILED,
    "duration_ms": $TOTAL_DUR
  },
  "assertions": [
    $JOINED_ASSERTIONS
  ]
}
EOF
else
    echo "=========================================="
    echo "Backup Verification: $PASSED/$TOTAL assertions passed in ${TOTAL_DUR}ms."
    echo "=========================================="
fi

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
