#!/usr/bin/env bash
# scripts/apply-phase7-antigravity.sh
# POSIX operator convergence runner for fidelacchius Feature 007 (Target Host Antigravity & Remote Control)
# Orchestrates execution of Ansible playbooks against the production host.
# Enforces explicit target readiness confirmation guard (FR-011).

set -euo pipefail

TARGET_HOST="192.168.4.57"
SSH_USER="admin"
IDENTITY_FILE=""
PLAYBOOK="playbooks/antigravity.yml"
TAGS=""
CHECK_MODE=false
CONFIRM_TARGET_READY=false
AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  -h, --host <IP|HOSTNAME>      Target host to converge (default: $TARGET_HOST)
  -u, --user <USERNAME>          SSH user for connection (default: $SSH_USER)
  -i, --identity <KEY_PATH>      SSH identity file (private key)
  -p, --playbook <PATH>          Playbook to run relative to ansible/ (default: $PLAYBOOK)
  -t, --tags <TAGS>              Comma-separated list of tags to execute
  --check                        Run in check mode (dry run / idempotency check)
  --age-key <KEY_PATH>           Path to operator age private key file
  --confirm-target-ready         Mandatory safety confirmation guard per FR-011
  --help                         Show this help message and exit
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
        --age-key)
            AGE_KEY_FILE="$2"
            shift 2
            ;;
        --confirm-target-ready)
            CONFIRM_TARGET_READY=true
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

# Enforce FR-011 safety confirmation guard
if [[ "$CONFIRM_TARGET_READY" != "true" ]]; then
    echo "ERROR: [SAFETY GUARD TRIGGERED] Missing mandatory confirmation flag: --confirm-target-ready" >&2
    echo "Per FR-011, automation MUST NOT execute against ${SSH_USER}@${TARGET_HOST} until target readiness is explicitly confirmed." >&2
    echo "To proceed, run: $0 --confirm-target-ready" >&2
    exit 3
fi

export SOPS_AGE_KEY_FILE="$AGE_KEY_FILE"

ANSIBLE_CMD=(ansible-playbook -i "$INVENTORY_FILE" "${ANSIBLE_DIR}/${PLAYBOOK}")

if [[ "$CHECK_MODE" == "true" ]]; then
    ANSIBLE_CMD+=(--check)
fi

if [[ -n "$TAGS" ]]; then
    ANSIBLE_CMD+=(--tags "$TAGS")
fi

if [[ -n "$IDENTITY_FILE" ]]; then
    ANSIBLE_CMD+=(--private-key "$IDENTITY_FILE")
fi

echo "=== fidelacchius Feature 007 Convergence Orchestrator ==="
echo "Target Host : ${SSH_USER}@${TARGET_HOST}"
echo "Playbook    : ${PLAYBOOK}"
if [[ "$CHECK_MODE" == "true" ]]; then echo "Mode        : Check Mode (Dry Run)"; fi
if [[ -n "$TAGS" ]]; then echo "Tags        : ${TAGS}"; fi
echo ""

cd "$ANSIBLE_DIR"
"${ANSIBLE_CMD[@]}"
