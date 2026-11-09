#!/usr/bin/env bash
# scripts/restore-from-b2.sh - Standalone Disaster Recovery Restoration from Backblaze B2
# Complies with DISASTER-RECOVERY-V1 contract
set -euo pipefail

SNAPSHOT="latest"
TARGET_DIR="/"
INCLUDE_PATH=""
FORCE=false
DRY_RUN=false

ACCOUNT_ID="${B2_ACCOUNT_ID:-}"
ACCOUNT_KEY="${B2_ACCOUNT_KEY:-}"
REPOSITORY="${RESTIC_REPOSITORY:-}"
PASSWORD="${RESTIC_PASSWORD:-}"

show_help() {
    cat << 'EOF'
Usage: restore-from-b2.sh [OPTIONS]

Options:
  --account-id ID       Backblaze B2 Application Key ID (or env B2_ACCOUNT_ID)
  --account-key KEY     Backblaze B2 Application Key (or env B2_ACCOUNT_KEY)
  --repository REPO     Restic repository URI, e.g. b2:fidelacchius-backups:fidelacchius (or env RESTIC_REPOSITORY)
  --password PASS       Restic repository password (or env RESTIC_PASSWORD)
  --snapshot ID         Snapshot ID to restore (default: latest)
  --target-dir DIR      Destination directory for restoration (default: /)
  --include-path PATH   Filter restoration to a specific subpath (e.g. etc/homelab/vault.yml)
  --force               Allow restoration into an existing non-empty target directory
  --dry-run             Test connectivity and list snapshot contents without restoring
  -h, --help            Show this help message
EOF
}

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --account-id)
            ACCOUNT_ID="$2"; shift 2 ;;
        --account-key)
            ACCOUNT_KEY="$2"; shift 2 ;;
        --repository)
            REPOSITORY="$2"; shift 2 ;;
        --password)
            PASSWORD="$2"; shift 2 ;;
        --snapshot)
            SNAPSHOT="$2"; shift 2 ;;
        --target-dir)
            TARGET_DIR="$2"; shift 2 ;;
        --include-path)
            INCLUDE_PATH="$2"; shift 2 ;;
        --force)
            FORCE=true; shift ;;
        --dry-run)
            DRY_RUN=true; shift ;;
        -h|--help)
            show_help; exit 0 ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            show_help
            exit 1 ;;
    esac
done

if [[ -z "$ACCOUNT_ID" || -z "$ACCOUNT_KEY" || -z "$REPOSITORY" || -z "$PASSWORD" ]]; then
    echo "ERROR: Missing required credentials. Supply via flags or B2_ACCOUNT_ID, B2_ACCOUNT_KEY, RESTIC_REPOSITORY, RESTIC_PASSWORD." >&2
    exit 1
fi

export B2_ACCOUNT_ID="$ACCOUNT_ID"
export B2_ACCOUNT_KEY="$ACCOUNT_KEY"
export RESTIC_REPOSITORY="$REPOSITORY"
export RESTIC_PASSWORD="$PASSWORD"

# Pre-flight dependency check
if ! command -v restic >/dev/null 2>&1; then
    echo "ERROR: restic binary not found on system." >&2
    echo "Install via: pacman -S restic, apt install restic, or download from https://github.com/restic/restic/releases" >&2
    exit 1
fi

# Target directory existence and non-empty check
if [[ "$DRY_RUN" != true ]]; then
    mkdir -p "$TARGET_DIR"
    if [ -d "$TARGET_DIR" ] && [ "$(ls -A "$TARGET_DIR" 2>/dev/null)" ]; then
        if [ "$FORCE" != true ]; then
            echo "ERROR: Target directory '$TARGET_DIR' is not empty. Re-run with --force to overwrite." >&2
            exit 1
        fi
    fi
fi

# Repository connectivity test
echo "Verifying repository connectivity and credentials..."
if ! restic -r "$RESTIC_REPOSITORY" snapshots >/dev/null 2>&1; then
    echo "ERROR: Failed to connect to repository or decrypt with provided credentials." >&2
    exit 1
fi

# Dry run execution
if [[ "$DRY_RUN" == true ]]; then
    echo "Dry run: listing contents of snapshot '$SNAPSHOT'..."
    if [[ -n "$INCLUDE_PATH" ]]; then
        CLEAN_PATH="${INCLUDE_PATH#/}"
        restic -r "$RESTIC_REPOSITORY" ls "$SNAPSHOT" "$CLEAN_PATH"
    else
        restic -r "$RESTIC_REPOSITORY" ls "$SNAPSHOT"
    fi
    echo "Dry run completed successfully."
    exit 0
fi

# Restore snapshot
echo "Restoring snapshot '$SNAPSHOT' to '$TARGET_DIR'..."
RESTORE_ARGS=("-r" "$RESTIC_REPOSITORY" "restore" "$SNAPSHOT" "--target" "$TARGET_DIR")
if [[ -n "$INCLUDE_PATH" ]]; then
    CLEAN_PATH="${INCLUDE_PATH#/}"
    RESTORE_ARGS+=("--include" "$CLEAN_PATH" "--include" "/$CLEAN_PATH")
fi

restic "${RESTORE_ARGS[@]}"
echo "Restic restore completed successfully."

# Permissions enforcement
RESOLVED_TARGET="$(cd "$TARGET_DIR" 2>/dev/null && pwd || echo "$TARGET_DIR")"

# Fix /etc/homelab/vault.yml permissions and sync to repo inventory if restoring to /
VAULT_CANDIDATE="$RESOLVED_TARGET/etc/homelab/vault.yml"
if [[ "$RESOLVED_TARGET" == "/" ]]; then
    VAULT_CANDIDATE="/etc/homelab/vault.yml"
fi

if [[ -f "$VAULT_CANDIDATE" ]]; then
    chmod 0600 "$VAULT_CANDIDATE"
    if [[ $(id -u) -eq 0 ]]; then
        chown root:root "$VAULT_CANDIDATE"
    fi
    echo "Enforced permissions 0600 on $VAULT_CANDIDATE"

    if [[ "$RESOLVED_TARGET" == "/" ]]; then
        for repo_dir in /home/admin/projects/homelab2 /home/admin/homelab2 /opt/homelab2; do
            if [[ -d "$repo_dir/ansible/inventory/group_vars/all" ]] && [[ ! -f "$repo_dir/ansible/inventory/group_vars/all/vault.yml" ]]; then
                cp "$VAULT_CANDIDATE" "$repo_dir/ansible/inventory/group_vars/all/vault.yml"
                chmod 0600 "$repo_dir/ansible/inventory/group_vars/all/vault.yml"
                if [[ $(id -u) -eq 0 ]] && id admin >/dev/null 2>&1; then
                    chown admin:users "$repo_dir/ansible/inventory/group_vars/all/vault.yml" 2>/dev/null || chown admin:admin "$repo_dir/ansible/inventory/group_vars/all/vault.yml" || true
                fi
                echo "Synced restored vault.yml to $repo_dir/ansible/inventory/group_vars/all/vault.yml"
            fi
        done
    fi
fi

# Fix /opt/services/vaultwarden/data permissions
SERVICES_DIR="$RESOLVED_TARGET/opt/services"
if [[ "$RESOLVED_TARGET" == "/" ]]; then
    SERVICES_DIR="/opt/services"
fi

if [[ -d "$SERVICES_DIR/vaultwarden/data" ]]; then
    chmod -R 0700 "$SERVICES_DIR/vaultwarden/data"
    if [[ $(id -u) -eq 0 ]]; then
        chown -R 1000:1000 "$SERVICES_DIR/vaultwarden/data"
    fi
    echo "Enforced permissions 0700 1000:1000 on $SERVICES_DIR/vaultwarden/data"
fi

# Post-restore hook execution (only when restoring to system root /)
if [[ "$RESOLVED_TARGET" == "/" ]]; then
    HOOK_DIR="/etc/homelab/backup.d"
    if [[ -d "$HOOK_DIR" ]]; then
        shopt -s nullglob
        HOOKS=("$HOOK_DIR"/*.sh)
        shopt -u nullglob
        if [[ ${#HOOKS[@]} -gt 0 ]]; then
            echo "Executing post-restore hooks in $HOOK_DIR..."
            for hook in "${HOOKS[@]}"; do
                if [[ -x "$hook" ]]; then
                    echo "Running hook: $hook post-restore"
                    "$hook" post-restore || {
                        echo "WARNING: Hook $hook post-restore failed with exit code $?" >&2
                    }
                fi
            done
        fi
    fi
fi

echo "Disaster recovery restore completed successfully."
