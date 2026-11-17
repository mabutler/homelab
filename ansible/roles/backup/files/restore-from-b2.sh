#!/usr/bin/env bash
# scripts/restore-from-b2.sh - Standalone Disaster Recovery Restoration from Backblaze B2
# Complies with STAGED-DISASTER-RECOVERY-V2 contract
set -euo pipefail

STAGE_RAW="all"
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
  --stage STAGE         Restoration stage: config (or 1), data (or 2), all (default: all)
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
        --stage)
            STAGE_RAW="$2"; shift 2 ;;
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

# Validate and normalize stage argument (prior to credentials or repository checks)
STAGE_NORM="$(echo "$STAGE_RAW" | tr '[:upper:]' '[:lower:]')"
case "$STAGE_NORM" in
    config|1)
        STAGE="STAGE_1_CONFIG"
        ;;
    data|2)
        STAGE="STAGE_2_DATA"
        ;;
    all|"")
        STAGE="STAGE_ALL"
        ;;
    *)
        echo "ERROR: Invalid stage '$STAGE_RAW'. Valid stage options: config, 1, data, 2, all" >&2
        exit 1
        ;;
esac

# Pre-flight dependency check
if ! command -v restic >/dev/null 2>&1; then
    echo "ERROR: restic binary not found on system." >&2
    echo "Install via: pacman -S restic, apt install restic, or download from https://github.com/restic/restic/releases" >&2
    exit 1
fi

if [[ -z "$ACCOUNT_ID" || -z "$ACCOUNT_KEY" || -z "$REPOSITORY" || -z "$PASSWORD" ]]; then
    echo "ERROR: Missing required credentials. Supply via flags or B2_ACCOUNT_ID, B2_ACCOUNT_KEY, RESTIC_REPOSITORY, RESTIC_PASSWORD." >&2
    exit 1
fi

export B2_ACCOUNT_ID="$ACCOUNT_ID"
export B2_ACCOUNT_KEY="$ACCOUNT_KEY"
export RESTIC_REPOSITORY="$REPOSITORY"
export RESTIC_PASSWORD="$PASSWORD"

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

# Resolve canonical target directory path
RESOLVED_TARGET="$(cd "$TARGET_DIR" 2>/dev/null && pwd || echo "$TARGET_DIR")"
if [[ "$RESOLVED_TARGET" == "/" ]]; then
    STORAGE_MOUNT="/mnt/storage"
else
    STORAGE_MOUNT="${RESOLVED_TARGET%/}/mnt/storage"
fi

# Mountpoint safety assertion: halt before extraction if /mnt/storage is unmounted
if [[ "$DRY_RUN" != true ]]; then
    CHECK_MOUNT=false
    if [[ "$STAGE" == "STAGE_2_DATA" ]]; then
        CHECK_MOUNT=true
    elif [[ "$STAGE" == "STAGE_ALL" ]]; then
        # Unified restore checks mountpoint if bulk storage is targeted
        if [[ -z "$INCLUDE_PATH" ]] || [[ "$INCLUDE_PATH" =~ ^/?mnt/storage ]]; then
            CHECK_MOUNT=true
        fi
    fi

    if [[ "$CHECK_MOUNT" == true ]]; then
        if ! mountpoint -q "$STORAGE_MOUNT"; then
            echo "CRITICAL: Storage mountpoint '$STORAGE_MOUNT' is not an active mountpoint. Aborting restoration to prevent root NVMe disk leakage." >&2
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

# Dry run execution: list candidate files matching stage filters
if [[ "$DRY_RUN" == true ]]; then
    echo "Dry run: listing contents of snapshot '$SNAPSHOT'..."
    if [[ "$STAGE" == "STAGE_1_CONFIG" ]]; then
        if [[ -n "$INCLUDE_PATH" ]]; then
            CLEAN_PATH="${INCLUDE_PATH#/}"
            restic -r "$RESTIC_REPOSITORY" ls "$SNAPSHOT" | grep -v '^snapshot ' | grep -v -E '(^|/)mnt/storage' | grep -F "$CLEAN_PATH" || true
        else
            restic -r "$RESTIC_REPOSITORY" ls "$SNAPSHOT" | grep -v '^snapshot ' | grep -v -E '(^|/)mnt/storage' | grep -E '(^|/)(etc/homelab|home/admin/\.ssh|home/admin/\.gemini|home/admin/projects)' || true
        fi
    elif [[ "$STAGE" == "STAGE_2_DATA" ]]; then
        if [[ -n "$INCLUDE_PATH" ]]; then
            CLEAN_PATH="${INCLUDE_PATH#/}"
            restic -r "$RESTIC_REPOSITORY" ls "$SNAPSHOT" | grep -v '^snapshot ' | grep -E '(^|/)(opt/services|mnt/storage/media/photos)' | grep -F "$CLEAN_PATH" || true
        else
            restic -r "$RESTIC_REPOSITORY" ls "$SNAPSHOT" | grep -v '^snapshot ' | grep -E '(^|/)(opt/services|mnt/storage/media/photos)' || true
        fi
    else
        # STAGE_ALL
        if [[ -n "$INCLUDE_PATH" ]]; then
            CLEAN_PATH="${INCLUDE_PATH#/}"
            restic -r "$RESTIC_REPOSITORY" ls "$SNAPSHOT" "$CLEAN_PATH" | grep -v '^snapshot ' || true
        else
            restic -r "$RESTIC_REPOSITORY" ls "$SNAPSHOT" | grep -v '^snapshot ' || true
        fi
    fi
    echo "Dry run completed successfully."
    exit 0
fi

# Construct restic restore command arguments
echo "Restoring snapshot '$SNAPSHOT' to '$TARGET_DIR' (Stage: $STAGE)..."
RESTORE_ARGS=("-r" "$RESTIC_REPOSITORY" "restore" "$SNAPSHOT" "--target" "$TARGET_DIR")

if [[ -n "$INCLUDE_PATH" ]]; then
    CLEAN_PATH="${INCLUDE_PATH#/}"
    RESTORE_ARGS+=("--include" "$CLEAN_PATH" "--include" "/$CLEAN_PATH")
else
    if [[ "$STAGE" == "STAGE_1_CONFIG" ]]; then
        RESTORE_ARGS+=(
            "--include" "/etc/homelab" "--include" "etc/homelab"
            "--include" "/home/admin/.ssh" "--include" "home/admin/.ssh"
            "--include" "/home/admin/.gemini" "--include" "home/admin/.gemini"
            "--include" "/home/admin/projects" "--include" "home/admin/projects"
        )
    elif [[ "$STAGE" == "STAGE_2_DATA" ]]; then
        RESTORE_ARGS+=(
            "--include" "/opt/services" "--include" "opt/services"
            "--include" "/mnt/storage/media/photos" "--include" "mnt/storage/media/photos"
        )
    fi
fi

restic "${RESTORE_ARGS[@]}"
echo "INFO: Restic restore completed successfully."

# Admin group resolution for ownership assignment
ADMIN_GROUP="users"
if ! getent group users >/dev/null 2>&1; then
    ADMIN_GROUP="admin"
fi

# Stage 1 / Stage All: Host Configuration, Secrets & Inventory Vault Sync
if [[ "$STAGE" == "STAGE_1_CONFIG" || "$STAGE" == "STAGE_ALL" ]]; then
    TARGET_PREFIX="$RESOLVED_TARGET"
    if [[ "$TARGET_PREFIX" == "/" ]]; then
        TARGET_PREFIX=""
    fi

    # Restrictive permissions on /etc/homelab secrets
    for secret_file in "$TARGET_PREFIX/etc/homelab/vault.yml" "$TARGET_PREFIX/etc/homelab/backup.env" "$TARGET_PREFIX/etc/homelab/monitoring.env"; do
        if [[ -f "$secret_file" ]]; then
            chmod 0600 "$secret_file"
            if [[ $(id -u) -eq 0 ]]; then
                chown root:root "$secret_file"
            fi
            echo "INFO: Enforced permissions 0600 root:root on $secret_file"
        fi
    done

    # SSH credentials permissions & ownership
    SSH_DIR="$TARGET_PREFIX/home/admin/.ssh"
    if [[ -d "$SSH_DIR" ]]; then
        chmod 0700 "$SSH_DIR"
        find "$SSH_DIR" -maxdepth 1 -type f -name 'id_*' ! -name '*.pub' -exec chmod 0600 {} +
        find "$SSH_DIR" -maxdepth 1 -type f -name '*.pub' -exec chmod 0644 {} +
        if [[ -f "$SSH_DIR/authorized_keys" ]]; then
            chmod 0600 "$SSH_DIR/authorized_keys"
        fi
        echo "INFO: Enforced permissions 0700/0600 on $SSH_DIR"
    fi

    # Gemini & Antigravity credentials permissions
    GEMINI_DIR="$TARGET_PREFIX/home/admin/.gemini"
    if [[ -d "$GEMINI_DIR" ]]; then
        chmod 0700 "$GEMINI_DIR"
        if [[ -d "$GEMINI_DIR/antigravity-cli" ]]; then
            chmod 0700 "$GEMINI_DIR/antigravity-cli"
        fi
        find "$GEMINI_DIR" -type f -name '*.json' -exec chmod 0600 {} +
        echo "INFO: Enforced permissions 0700/0600 on $GEMINI_DIR"
    fi

    # Ownership enforcement for /home/admin trees when running as root
    if [[ $(id -u) -eq 0 ]] && id admin >/dev/null 2>&1; then
        for admin_tree in "$SSH_DIR" "$GEMINI_DIR" "$TARGET_PREFIX/home/admin/projects"; do
            if [[ -e "$admin_tree" ]]; then
                chown -R "admin:$ADMIN_GROUP" "$admin_tree"
            fi
        done
    fi

    # Synchronize restored vault.yml into local Ansible repository checkouts
    VAULT_SRC="$TARGET_PREFIX/etc/homelab/vault.yml"
    if [[ "$RESOLVED_TARGET" == "/" && -f "$VAULT_SRC" ]]; then
        for repo_dir in /home/admin/projects/homelab2 /home/admin/homelab2 /opt/homelab2; do
            if [[ -d "$repo_dir/ansible/inventory/group_vars/all" ]]; then
                cp "$VAULT_SRC" "$repo_dir/ansible/inventory/group_vars/all/vault.yml"
                chmod 0600 "$repo_dir/ansible/inventory/group_vars/all/vault.yml"
                if [[ $(id -u) -eq 0 ]] && id admin >/dev/null 2>&1; then
                    chown "admin:$ADMIN_GROUP" "$repo_dir/ansible/inventory/group_vars/all/vault.yml" 2>/dev/null || chown admin "$repo_dir/ansible/inventory/group_vars/all/vault.yml" || true
                fi
                echo "INFO: Synced restored vault.yml to $repo_dir/ansible/inventory/group_vars/all/vault.yml"
            fi
        done
    fi
fi

# Stage 2 / Stage All: Application Services & Storage Pool Permissions
if [[ "$STAGE" == "STAGE_2_DATA" || "$STAGE" == "STAGE_ALL" ]]; then
    TARGET_PREFIX="$RESOLVED_TARGET"
    if [[ "$TARGET_PREFIX" == "/" ]]; then
        TARGET_PREFIX=""
    fi

    # Application service state permissions
    SERVICES_DIR="$TARGET_PREFIX/opt/services"
    if [[ -d "$SERVICES_DIR/vaultwarden/data" ]]; then
        chmod -R 0700 "$SERVICES_DIR/vaultwarden/data"
        if [[ $(id -u) -eq 0 ]]; then
            chown -R 1000:1000 "$SERVICES_DIR/vaultwarden/data"
        fi
        echo "INFO: Enforced permissions 0700 1000:1000 on $SERVICES_DIR/vaultwarden/data"
    fi

    if [[ -d "$SERVICES_DIR" ]]; then
        find "$SERVICES_DIR" -maxdepth 2 -type f -name '.env' -exec chmod 0600 {} +
    fi

    # Bulk media storage pool permissions (2775 admin:storage)
    PHOTOS_DIR="$TARGET_PREFIX/mnt/storage/media/photos"
    if [[ -d "$PHOTOS_DIR" ]]; then
        chmod 2775 "$PHOTOS_DIR"
        if [[ $(id -u) -eq 0 ]]; then
            chown 1000:1001 "$PHOTOS_DIR" 2>/dev/null || true
        fi
        echo "INFO: Enforced permissions 2775 on $PHOTOS_DIR"
    fi
fi

# Stage 2 / Stage All: Container Startup & Post-Restore Database Hooks (only when restoring to /)
if [[ ("$STAGE" == "STAGE_2_DATA" || "$STAGE" == "STAGE_ALL") && "$RESOLVED_TARGET" == "/" ]]; then
    # Ensure Docker daemon and application container units are running
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl list-unit-files docker.service >/dev/null 2>&1; then
            if ! systemctl is-active docker.service >/dev/null 2>&1; then
                echo "INFO: Starting docker.service for post-restore hooks..."
                systemctl start docker.service || echo "WARN: Failed to start docker.service" >&2
            fi
        fi

        for svc in vaultwarden.service frigate.service immich.service; do
            if systemctl list-unit-files "$svc" >/dev/null 2>&1; then
                if ! systemctl is-active "$svc" >/dev/null 2>&1; then
                    echo "INFO: Starting $svc..."
                    systemctl start "$svc" || echo "WARN: Failed to start $svc" >&2
                fi
            fi
        done
    fi

    # Execute post-restore database hooks
    HOOK_DIR="/etc/homelab/backup.d"
    if [[ -d "$HOOK_DIR" ]]; then
        shopt -s nullglob
        HOOKS=("$HOOK_DIR"/*.sh)
        shopt -u nullglob
        if [[ ${#HOOKS[@]} -gt 0 ]]; then
            echo "INFO: Executing post-restore hooks in $HOOK_DIR..."
            for hook in "${HOOKS[@]}"; do
                if [[ -x "$hook" ]]; then
                    echo "INFO: Running hook: $hook post-restore"
                    if ! "$hook" post-restore; then
                        echo "WARN: Hook $hook post-restore failed with exit code $?" >&2
                    fi
                fi
            done
        fi
    fi
fi

echo "INFO: Disaster recovery restore completed successfully."
