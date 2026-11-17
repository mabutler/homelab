# Phase 0 Research: Staged Backblaze B2 Disaster Recovery Restoration

**Feature**: `014-staged-b2-restore`  
**Date**: 2026-11-10  
**Status**: Completed  

---

## 1. Stage Parameter Normalization & CLI Semantics

- **Decision**: Support `--stage <value>` in `scripts/restore-from-b2.sh` (and `ansible/roles/backup/files/restore-from-b2.sh`) and `-Stage <value>` in `scripts/restore-from-b2.ps1`, accepting `config`, `1`, `data`, `2`, and `all` case-insensitively, defaulting to `all` when omitted.
- **Rationale**:
  - Operators recovering bare-metal hardware under stress may type either semantic stage names (`config`, `data`) or numeric phase shorthand (`1`, `2`).
  - Defaulting to `all` when `--stage` is omitted preserves 100% backward compatibility with existing single-file recovery invocations (such as `BK-008` in `scripts/verify-phase5-backup.sh` which passes `--target-dir /tmp/b2-test-restore --include-path etc/homelab/vault.yml --force`).
  - Normalizing input via `${STAGE,,}` in Bash 5.x (and `[ValidateSet("config", "1", "data", "2", "all")]` in PowerShell 7+) and rejecting unrecognized values immediately with exit code `1` before repository or filesystem operations satisfies Constitution Principle II (Fail Closed on Rejected Operations).
- **Alternatives Considered**:
  - Separate scripts (`restore-stage1.sh`, `restore-stage2.sh`): Rejected because duplicating credential parsing, pre-flight `restic` checks, and repository connectivity verification violates Principle IV (Single Source of Truth) and increases maintenance surface.
  - Requiring `--stage` on every invocation: Rejected because it breaks backward compatibility with `BK-008` (`verify-phase5-backup.sh`) and single-path `--include-path` administrative restores (FR-012).

---

## 2. Stage 1 Path Filtering & Bulk Data Exclusion (`config` / `1`)

- **Decision**: When `--stage config` or `--stage 1` is selected, restrict Restic extraction (and `--dry-run` listing) to the four bootstrap configuration roots:
  1. `/etc/homelab`
  2. `/home/admin/.ssh`
  3. `/home/admin/.gemini`
  4. `/home/admin/projects`
  Additionally append `--exclude /mnt/storage` and `--exclude mnt/storage` to `restic restore` and explicitly skip `/etc/homelab/backup.d/*.sh` post-restore hooks.
- **Rationale**:
  - On a freshly provisioned Arch Linux node (post-Phase 1 live USB install), neither Docker Engine nor the MergerFS `/mnt/storage` pool exists yet.
  - Extracting `/mnt/storage/media/photos` prior to running `ansible/playbooks/site.yml` would write hundreds of gigabytes of media directly onto the root NVMe partition (`/dev/nvme0n1p2`), and executing `/etc/homelab/backup.d/30-immich.sh post-restore` would fail because `docker` and `immich.service` are not yet installed.
  - Restoring `/etc/homelab` (containing `vault.yml`, `monitoring.env`, `backup.env`, `apps/`, and `backup.d/`), `/home/admin/.ssh` (GitHub deploy key `id_ed25519_github` and `authorized_keys`), `/home/admin/.gemini` (Antigravity OAuth credentials), and `/home/admin/projects` provides every secret and repository file required for `ansible-playbook -i inventory/hosts.yml playbooks/site.yml` to converge the entire platform cleanly.
  - If `--include-path` is also supplied alongside `--stage`, the explicit `--include-path` further narrows the filter while retaining the stage's `/mnt/storage` exclusion guard.
- **Alternatives Considered**:
  - Relying solely on `--exclude /mnt/storage` without explicit `--include` roots in Stage 1: Rejected because `/opt/services` contains application data and database dumps that belong to Stage 2 after Docker and storage users/groups (`storage` GID `1001`) are created by Ansible.

---

## 3. Stage 1 Secret Permissions & Inventory Vault Synchronization

- **Decision**: Following Stage 1 (or `all`) file extraction, enforce strict filesystem permissions and synchronize `/etc/homelab/vault.yml` to `ansible/inventory/group_vars/all/vault.yml`:
  - `/etc/homelab/vault.yml`, `/etc/homelab/backup.env`, `/etc/homelab/monitoring.env`: `0600 root:root`
  - `/home/admin/.ssh`: directory `0700`, private keys (`id_*` excluding `*.pub`) `0600`, public keys/authorized_keys `0644` / `0600`
  - `/home/admin/.gemini`: directory `0700`, `oauth_creds.json`, `google_accounts.json`, and `antigravity-cli/settings.json` `0600`
  - Ownership of restored `/home/admin/{.ssh,.gemini,.config,projects}` paths set to `admin:users` (falling back to `admin:admin`) when running as `root`
  - Copy restored `/etc/homelab/vault.yml` to `/home/admin/projects/homelab2/ansible/inventory/group_vars/all/vault.yml` (and any existing repo checkouts in `/home/admin/homelab2` or `/opt/homelab2`) with mode `0600` and owner `admin`, overwriting or populating the missing gitignored inventory vault so `site.yml` pre-tasks (`Verify vault.yml exists on controller`) pass immediately.
- **Rationale**:
  - `ansible/playbooks/site.yml` lines 8–26 enforce a hard pre-task check asserting `{{ inventory_dir }}/group_vars/all/vault.yml` exists on the controller before running any roles.
  - OpenSSH (`sshd` and `ssh` client) refuses to use private keys or `.ssh` directories if permissions are broader than `0600`/`0700`.
- **Alternatives Considered**:
  - Requiring manual `cp /etc/homelab/vault.yml ~/projects/homelab2/ansible/inventory/group_vars/all/vault.yml` and manual `chown`/`chmod` after Stage 1: Rejected because manual permission fixing is error-prone and violates FR-004 and SC-004.

---

## 4. Stage 2 Active Mountpoint Assertion & NVMe Leakage Prevention (`data` / `2`)

- **Decision**: Before initiating bulk file extraction in Stage 2 (`--stage data` or `--stage 2`), or in `--stage all` when bulk storage paths are targeted (`--target-dir /` without a non-storage `--include-path`, or when `--include-path` targets `mnt/storage`), execute `mountpoint -q "${RESOLVED_TARGET%/}/mnt/storage"` (which resolves to `mountpoint -q /mnt/storage` when restoring to `/`). If `/mnt/storage` is not an active mountpoint and `--dry-run` is not set:
  - Emit a `CRITICAL:` diagnostic message to `stderr` explaining that `/mnt/storage` is not an active mountpoint and restoration was aborted to prevent root NVMe filesystem leakage.
  - Exit immediately with code `1` before invoking `restic restore` or modifying disk state.
  - Additionally, provide an explicit `--storage-mount-path <path>` override (defaulting to `/mnt/storage` when `TARGET_DIR` is `/`, or `${RESOLVED_TARGET%/}/mnt/storage` when testing mount assertions in isolated target dirs) or evaluate `mountpoint -q` directly on `${RESOLVED_TARGET%/}/mnt/storage` so acceptance verification can deterministically test the unmounted-storage rejection gate without unmounting production MergerFS!
- **Rationale**:
  - Checking `mountpoint -q "${RESOLVED_TARGET%/}/mnt/storage"` checks `/mnt/storage` when `--target-dir /` (the default) is used, and checks `<target-dir>/mnt/storage` when a custom `--target-dir` is used with `--stage data`.
  - This allows `scripts/verify-phase5-backup.sh` to test the unmounted storage guard safely and deterministically on the live production server by running `restore-from-b2.sh --stage data --target-dir /tmp/b2-unmounted-test --force` (where `/tmp/b2-unmounted-test/mnt/storage` is an unmounted directory) and verifying that it fails closed with exit code `1` and `CRITICAL` stderr output without touching the live `/mnt/storage` MergerFS mount!
- **Alternatives Considered**:
  - Checking `df -T /mnt/storage | grep fuse.mergerfs`: Rejected as sole check because `mountpoint -q` is the standard POSIX/util-linux kernel mountpoint table check specified in FR-005 (`mountpoint -q /mnt/storage`) and works across any mounted filesystem type.

---

## 5. Stage 2 Bulk Restoration, Container Startup & Database Hooks (`data` / `2`)

- **Decision**: When `--stage data` or `--stage 2` executes:
  1. Restore `/opt/services` and `/mnt/storage/media/photos` from the Restic snapshot.
  2. Enforce ownership and permissions on restored service and media directories:
     - `/opt/services/vaultwarden/data`: `0700` owned by `1000:1000`
     - `/mnt/storage/media/photos`: `2775` owned by `1000:1001` (`admin:storage`) if directory exists
  3. When restoring to `/`:
     - Ensure `docker.service` is active (`systemctl start docker.service` if installed).
     - Ensure deployed application systemd services (`vaultwarden.service`, `frigate.service`, `immich.service`) are started if their unit files exist on the system so database containers (such as `immich_postgres`) are running prior to hook execution.
     - Execute all executable `/etc/homelab/backup.d/*.sh` scripts with the `post-restore` argument.
- **Rationale**:
  - While `10-vaultwarden.sh` and `20-frigate.sh` copy offline SQLite snapshot files (`snapshot.sqlite3` -> `db.sqlite3` / `frigate.db`), `30-immich.sh post-restore` executes `docker compose -f /opt/services/immich/compose.yml exec -T database pg_restore ...` which requires the `database` container in `immich.service` to be running.
  - Ensuring `docker.service` and installed application services are started before running `post-restore` hooks satisfies User Story 4 and FR-008 automatically.
- **Alternatives Considered**:
  - Requiring the operator to manually start Docker and run `/etc/homelab/backup.d/30-immich.sh post-restore` after Stage 2: Rejected because FR-008 explicitly requires Stage 2 to ensure container runtimes are active and execute all post-restore hooks in `/etc/homelab/backup.d/*.sh`.

---

## 6. Acceptance Verification Strategy (Principle III Compliance)

- **Decision**: Extend `scripts/verify-phase5-backup.sh` and `ansible/playbooks/verify-phase5-backup.yml` (keeping existing assertions `BK-001` through `BK-008` intact and adding staged restore assertions `BK-009` through `BK-012`) to verify:
  - `BK-009`: Stage 1 (`--stage config --dry-run`) lists configuration paths (`/etc/homelab`) and excludes `/mnt/storage` bulk paths.
  - `BK-010`: Stage 2 unmounted storage guard (`--stage data --target-dir /tmp/b2-unmounted-test --force`) aborts immediately with exit code `1` and `CRITICAL` message before downloading files.
  - `BK-011`: Invalid stage rejection (`--stage invalid`) fails closed with exit code `1`.
  - `BK-012`: Non-destructive Stage 1 restore rehearsal (`--stage 1 --target-dir /tmp/b2-stage1-test --include-path etc/homelab/vault.yml --force`) restores `vault.yml` with mode `0600` without executing post-restore hooks or creating `/mnt/storage`.
- **Rationale**:
  - Complies strictly with Constitution Principle III (Zero Automated Unit Tests; verification exclusively via static linters `bash -n`, `shellcheck`, `ansible-lint`, and live acceptance scripts `scripts/verify-phase5-backup.sh`).
  - Note on filename reference: Therepository's Phase 5 backup verification script is `scripts/verify-phase5-backup.sh` (Feature 006 was numbered `006-backblaze-backup-restore` within Phase 5). Extending `scripts/verify-phase5-backup.sh` and `ansible/playbooks/verify-phase5-backup.yml` maintains a single authoritative backup verification suite.
