#!/usr/bin/env bash
# scripts/apply-phase8-monitoring.sh
# POSIX operator convergence runner for fidelacchius Phase 8: Platform Monitoring & Alerting (ntfy & Healthchecks)
# Orchestrates execution of Ansible playbooks against the production host.

set -euo pipefail

TARGET_HOST="192.168.4.57"
SSH_USER="admin"
IDENTITY_FILE=""
PLAYBOOK="playbooks/monitoring.yml"
TAGS=""
CHECK_MODE=false

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  -h, --host <IP|HOSTNAME>   Target host to converge (default: $TARGET_HOST)
  -u, --user <USERNAME>      SSH user for connection (default: $SSH_USER)
  -i, --identity <KEY_PATH>  SSH identity file (private key)
  -p, --playbook <PATH>      Playbook to run relative to ansible/ (default: $PLAYBOOK)
  -t, --tags <TAGS>          Comma-separated list of tags to execute
  --check                    Run in check mode (dry run / idempotency check)
  --help                     Show this help message and exit
EOF
    exit 0
}

if SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)"; then
    REPO_ROOT="$SCRIPT_DIR"
else
    REPO_ROOT="$(pwd)"
fi
ANSIBLE_DIR="${REPO_ROOT}/ansible"
INVENTORY_FILE="${ANSIBLE_DIR}/inventory/hosts.yml"

# Parse inventory defaults if hosts.yml exists
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
        -p|--playbook)
            PLAYBOOK="$2"
            shift 2
            ;;
        -t|--tags)
            TAGS="$2"
            shift 2
            ;;
        --check)
            CHECK_MODE=true
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

echo "=== fidelacchius Phase 8 Platform Monitoring Convergence Orchestrator ==="
echo "Target Host : ${SSH_USER}@${TARGET_HOST}"
echo "Playbook    : ${PLAYBOOK}"
if [[ "$CHECK_MODE" == "true" ]]; then echo "Mode        : Check Mode (Dry Run)"; fi
if [[ -n "$TAGS" ]]; then echo "Tags        : ${TAGS}"; fi

if command -v ansible-playbook >/dev/null 2>&1; then
    echo -e "\n[Local Controller] Executing ansible-playbook..."
    cd "${ANSIBLE_DIR}"
    ANSIBLE_ARGS=(-i inventory/hosts.yml "$PLAYBOOK")
    if [[ "$TARGET_HOST" == "localhost" ]] || [[ "$TARGET_HOST" == "127.0.0.1" ]] || ip -4 addr show 2>/dev/null | grep -q "inet ${TARGET_HOST}/" || [[ "$(uname -n 2>/dev/null || echo '')" == "fidelacchius" ]]; then
        ANSIBLE_ARGS+=(--connection=local)
    fi
    if [[ "$CHECK_MODE" == "true" ]]; then ANSIBLE_ARGS+=(--check); fi
    if [[ -n "$TAGS" ]]; then ANSIBLE_ARGS+=(--tags "$TAGS"); fi
    exec ansible-playbook "${ANSIBLE_ARGS[@]}"
else
    echo -e "\n[Remote Remoting] Native ansible-playbook not found locally."
    echo "Connecting to ${SSH_USER}@${TARGET_HOST}..."

    SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=30)
    if [[ -n "$IDENTITY_FILE" ]]; then
        SSH_OPTS+=(-i "$IDENTITY_FILE")
    fi

    # Sync ansible and scripts directory via tar
    tar -czf - -C "${REPO_ROOT}" ansible scripts | ssh "${SSH_OPTS[@]}" "${SSH_USER}@${TARGET_HOST}" "rm -rf /tmp/homelab2-ansible && mkdir -p /tmp/homelab2-ansible && tar -xzf - -C /tmp/homelab2-ansible"

    REMOTE_CMD="cd /tmp/homelab2-ansible/ansible && ansible-playbook -i inventory/hosts.yml ${PLAYBOOK} --connection=local"
    if [[ "$CHECK_MODE" == "true" ]]; then REMOTE_CMD+=" --check"; fi
    if [[ -n "$TAGS" ]]; then REMOTE_CMD+=" --tags '${TAGS}'"; fi

    ssh "${SSH_OPTS[@]}" -t "${SSH_USER}@${TARGET_HOST}" "$REMOTE_CMD"
    REMOTE_EXIT=$?

    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${TARGET_HOST}" "rm -rf /tmp/homelab2-ansible"
    exit $REMOTE_EXIT
fi
