#!/usr/bin/env bash
# scripts/apply-phase2.sh
# POSIX operator convergence runner for fidelacchius Phase 2 (Core Hardening & IaC)
# Orchestrates execution of Ansible playbooks against the production host.

set -euo pipefail

TARGET_HOST="192.168.4.57"
SSH_USER="admin"
IDENTITY_FILE=""
PLAYBOOK="playbooks/site.yml"
TAGS=""
CHECK_MODE=false
AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  -h, --host <IP|HOSTNAME>   Target host to converge (default: $TARGET_HOST)
  -u, --user <USERNAME>       SSH user for connection (default: $SSH_USER)
  -i, --identity <KEY_PATH>   SSH identity file (private key)
  -p, --playbook <PATH>       Playbook to run relative to ansible/ (default: $PLAYBOOK)
  -t, --tags <TAGS>           Comma-separated list of tags to execute
  --check                     Run in check mode (dry run / idempotency check)
  --age-key <KEY_PATH>        Path to operator age private key file
  --help                      Show this help message and exit
EOF
    exit 0
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
        --age-key)
            AGE_KEY_FILE="$2"
            shift 2
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

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5)
if [[ -n "$IDENTITY_FILE" ]]; then
    SSH_OPTS+=(-i "$IDENTITY_FILE")
fi

echo "=== fidelacchius Phase 2 Convergence Orchestrator (POSIX) ==="
echo "Target Host : ${SSH_USER}@${TARGET_HOST}"
echo "Playbook    : ${PLAYBOOK}"
if [[ "$CHECK_MODE" == "true" ]]; then echo "Mode        : Check Mode (Dry Run)"; fi
if [[ -n "$TAGS" ]]; then echo "Tags        : ${TAGS}"; fi

if command -v ansible-playbook >/dev/null 2>&1; then
    echo -e "\n[Local Controller] Executing ansible-playbook locally..."
    cd "${ANSIBLE_DIR}"
    ANSIBLE_ARGS=(-i inventory/hosts.yml "$PLAYBOOK")
    if [[ "$CHECK_MODE" == "true" ]]; then ANSIBLE_ARGS+=(--check); fi
    if [[ -n "$TAGS" ]]; then ANSIBLE_ARGS+=(--tags "$TAGS"); fi
    export SOPS_AGE_KEY_FILE="$AGE_KEY_FILE"
    exec ansible-playbook "${ANSIBLE_ARGS[@]}"
else
    echo -e "\n[Remote Remoting] Native ansible-playbook not found on local controller."
    echo "Syncing ansible project and orchestrating execution on ${SSH_USER}@${TARGET_HOST}..."

    # Test SSH connection
    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${TARGET_HOST}" "uname -s" >/dev/null

    # Sync age key if present locally
    if [[ -f "$AGE_KEY_FILE" ]]; then
        echo "Syncing age key to target host..."
        ssh "${SSH_OPTS[@]}" "${SSH_USER}@${TARGET_HOST}" "mkdir -p -m 700 ~/.config/sops/age && cat > ~/.config/sops/age/keys.txt && chmod 600 ~/.config/sops/age/keys.txt" < "$AGE_KEY_FILE"
    fi

    # Sync ansible directory via tar
    echo "Syncing Ansible workspace to /tmp/homelab2-ansible on target..."
    tar -czf - -C "${REPO_ROOT}" ansible | ssh "${SSH_OPTS[@]}" "${SSH_USER}@${TARGET_HOST}" "rm -rf /tmp/homelab2-ansible && mkdir -p /tmp/homelab2-ansible && tar -xzf - -C /tmp/homelab2-ansible"

    # Run playbook on remote host
    echo -e "\nExecuting playbook on target host (${PLAYBOOK})..."
    REMOTE_CMD="cd /tmp/homelab2-ansible/ansible && export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt && export ANSIBLE_PIPELINING=False && ansible-playbook -i inventory/hosts.yml ${PLAYBOOK} --connection=local"
    if [[ "$CHECK_MODE" == "true" ]]; then REMOTE_CMD+=" --check"; fi
    if [[ -n "$TAGS" ]]; then REMOTE_CMD+=" --tags '${TAGS}'"; fi

    ssh "${SSH_OPTS[@]}" -t "${SSH_USER}@${TARGET_HOST}" "$REMOTE_CMD"
    REMOTE_EXIT=$?

    # Cleanup remote directory
    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${TARGET_HOST}" "rm -rf /tmp/homelab2-ansible"
    exit $REMOTE_EXIT
fi
