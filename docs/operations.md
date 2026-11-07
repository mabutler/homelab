# Operational Runbook: Target Host Antigravity & Remote Control

This runbook documents day-to-day operations, lifecycle management, troubleshooting, and disaster recovery procedures for the Google Antigravity Remote Control daemon on `fidelacchius` (`admin@192.168.4.57`).

---

## 1. Overview & Architecture

The Google Antigravity CLI (`agy`) runs as a persistent background daemon (`agy-remote-control.service`) under systemd user supervision on the target server. It connects outward via WSS/HTTPS to Google Antigravity servers, allowing the operator to manage, inspect, and build out homelab features remotely from mobile devices or web browsers without requiring inbound firewall ports.

- **Operator User**: `admin`
- **Binary Path**: `/home/admin/.local/bin/agy` (symlinked from `/usr/local/bin/agy`)
- **Systemd Unit**: `/home/admin/.config/systemd/user/agy-remote-control.service`
- **Instance Name**: `homelab2-target`
- **Configuration**: `/home/admin/.gemini/antigravity-cli/settings.json` (mode `0600 admin:admin`)
- **Workspace**: `/home/admin/homelab2` (with `.worktrees/` directory for isolated feature development)
- **Git Key**: `/home/admin/.ssh/id_ed25519_github` (dedicated deploy key)

---

## 2. Common Operational Commands

### 2.1 Service Management

The daemon is supervised by the `admin` user's systemd instance. To inspect or control the service:

```bash
# Check service status via CLI
agy remote-control status

# Check systemd user service state
systemctl --user status agy-remote-control.service

# Restart the daemon
systemctl --user restart agy-remote-control.service

# View live streaming daemon logs
journalctl --user -u agy-remote-control.service -f --no-pager

# View recent 50 lines of logs
journalctl --user -u agy-remote-control.service -n 50 --no-pager
```

### 2.2 Boot Persistence & Lingering

User lingering is enabled via `loginctl enable-linger admin`. This ensures `systemd --user` launches at boot without requiring an active SSH session.
To verify:
```bash
test -f /var/lib/systemd/linger/admin && echo "Lingering enabled"
```

---

## 3. Remote Development Workflow (Isolated Worktrees)

When executing tasks via Remote Control:
1. Always create feature worktrees under `/home/admin/homelab2/.worktrees/`:
   ```bash
   git -C /home/admin/homelab2 worktree add .worktrees/<feature-name> -b <feature-name>
   ```
2. Develop, test, and run playbooks locally inside the worktree directory.
3. Push changes to GitHub using the dedicated deploy key:
   ```bash
   git push -u origin <feature-name>
   ```
4. Remove the worktree upon PR merge:
   ```bash
   git -C /home/admin/homelab2 worktree remove .worktrees/<feature-name>
   ```

---

## 4. Deployment & Verification Orchestration

### 4.1 Deployment (Enforces FR-011 Safety Guard)

From workstation (PowerShell):
```powershell
./scripts/apply-phase7-antigravity.ps1 -HostAddress 192.168.4.57 -User admin -ConfirmTargetReady
```

From server (Bash):
```bash
./scripts/apply-phase7-antigravity.sh --confirm-target-ready
```

### 4.2 Automated Acceptance Verification (AG-001 through AG-008)

From workstation:
```powershell
./scripts/verify-phase7-antigravity.ps1 -TargetHost 192.168.4.57 -User admin
```

From server:
```bash
./scripts/verify-phase7-antigravity.sh
# or structured JSON:
./scripts/verify-phase7-antigravity.sh --json
```

---

## 5. Backup & Disaster Recovery

### 5.1 Centralized Backup Coverage
Authentication profiles and settings are automatically included in daily Backblaze B2 snapshots:
- `/home/admin/.gemini/oauth_creds.json`
- `/home/admin/.gemini/google_accounts.json`
- `/home/admin/.gemini/antigravity-cli/settings.json`
- `/home/admin/.ssh/id_ed25519_github`
- `/home/admin/.ssh/id_ed25519_github.pub`

Ephemeral caches, model files, crash telemetry, and Git databases are excluded to avoid backup bloat.

### 5.2 Recovery Procedure
1. Run `scripts/restore-from-b2.sh` to extract the latest snapshot.
2. Re-apply the deployment playbook:
   ```bash
   ./scripts/apply-phase7-antigravity.sh --confirm-target-ready
   ```
3. The daemon starts immediately with existing credentials without requiring interactive browser OAuth.

### 5.3 Legacy Test Bucket & Application Key Retirement
Following verified cutover to the official Backblaze B2 bucket `fidelacchius-backups` (`b2:fidelacchius-backups:fidelacchius`):
1. Log into the Backblaze B2 web console (`https://secure.backblaze.com/b2_buckets.htm`).
2. Navigate to **Application Keys**:
   - Locate the legacy key previously named `homelab` (`keyID: 0058d446d9d51d00000000002`).
   - Click **Delete Key** and confirm deletion.
3. Navigate to **Buckets**:
   - Locate the legacy test bucket `homelab2-fidelachius`.
   - Confirm all production snapshots are present in `fidelacchius-backups`.
   - Click **Bucket Settings** -> **Delete Bucket** (or remove residual test files then delete bucket).
4. All backup operations and scheduled systemd timers now exclusively target `b2:fidelacchius-backups:fidelacchius`.

---

## 6. Immich Photo Management Platform

### 6.1 Architecture & Ingress

The Immich photo and video management platform is deployed as a containerized multi-service stack supervised by systemd (`immich.service`) located at `/opt/services/immich`.
- **Services**: `immich-server` (`v1.118.2`), `immich-machine-learning`, `database` (`tensorchord/pgvecto-rs:pg16-v0.2.1`), and `redis` (`6.2-alpine`).
- **Internal Loopback Binding**: `127.0.0.1:2283` (no direct external exposure).
- **Reverse Proxy Ingress**: Fronted by Caddy (`/etc/caddy/conf.d/30-immich.caddy`) at:
  - Local LAN: `https://photos.lan` (or configured `$HOMELAB_DOMAIN`)
  - Tailscale VPN: `https://photos.fidelacchius.ts.net`
  - Ingress Buffer: Configured with `max_size 50GB` for multi-gigabyte video uploads.

### 6.2 Initial Admin Account Setup

1. Open your browser and navigate to `https://photos.fidelacchius.ts.net` (while connected to Tailscale) or `http://photos.lan`.
2. The initial setup screen will prompt you to create the administrator account (email, name, password).
3. Complete onboarding by establishing default storage and display preferences.

### 6.3 Mobile Application Configuration

1. Install the official Immich app on iOS (App Store) or Android (Google Play / F-Droid).
2. On first launch, enter the server URL:
   - For remote / offsite synchronization: `https://photos.fidelacchius.ts.net` (ensure Tailscale client is active on device).
   - For local synchronization: `https://photos.lan`.
3. Log in using your user credentials.
4. Enable background synchronization and grant photo library permissions.

### 6.4 Storage Architecture & Permissions

Immich operates across two distinct storage tiers:
- **Tier 0 Fast NVMe** (`/opt/services/immich`):
  - `compose.yml` and `.env` (mode `0600`)
  - `data/postgres/`: PostgreSQL database cluster with `pgvector` embeddings (`999:999`, mode `0700`)
  - `data/thumbs/`: Pre-generated image and video thumbnails (`1000:1001`, mode `0755`)
  - `data/model-cache/`: Downloaded machine learning weights (`1000:1001`, mode `0755`)
  - `data/profile/`: User profile images (`1000:1001`, mode `0755`)
  - `backups/`: Transactional database dump staging (`root:root`, mode `0750`)
- **Tier 1 Pooled Bulk Storage** (`/mnt/storage/media/photos`):
  - `library/`: Primary full-resolution photo and video assets
  - `upload/`: Temporary multipart upload staging buffer
  - `encoded-video/`: Transcoded web video streaming cache
  - Enforces `admin:storage` (`PUID=1000`/`PGID=1001`) ownership and `2775` setgid flags.

### 6.5 Hardware Acceleration & iGPU Video Transcoding

Hardware-accelerated video decoding and transcoding utilizes the host's Intel UHD Graphics 770 iGPU (`00:02.0`):
- Stable device paths `/dev/dri/by-path/pci-0000:00:02.0-render` and `...-card` are passed into the `immich-server` container.
- `LIBVA_DRIVER_NAME=iHD` is declared in the container environment.
- The host's discrete AMD Radeon RX 6700 XT GPU is strictly isolated from the stack.

### 6.6 Continuous Disaster Recovery & Backup Restoration

Disaster recovery is orchestrated via `/etc/homelab/backup.d/30-immich.sh`:
- **Pre-Backup Trigger**:
  Executes transactional `pg_dump` within the PostgreSQL container, emitting a validated custom-format archive to `/opt/services/immich/backups/immich_db_backup.dump`.
- **Restic Offsite Synchronization**:
  Restic captures `/opt/services/immich` (configuration, credentials, database dump, profile images) and `/mnt/storage/media/photos/library` to Backblaze B2. Regenerable caches (`thumbs`, `model-cache`, `upload`, `encoded-video`, live `postgres` cluster) are excluded.
- **Database Restoration Procedure**:
  To restore the database cluster from a snapshot:
  ```bash
  # Ensure the container stack is active
  systemctl start immich.service

  # Execute restoration hook
  sudo /etc/homelab/backup.d/30-immich.sh post-restore
  ```

### 6.7 Operational & Verification Commands

```bash
# Check systemd service status
systemctl status immich.service

# Restart the Immich stack
sudo systemctl restart immich.service

# View live container logs
sudo docker compose -f /opt/services/immich/compose.yml logs -f

# Run the 9-point acceptance verification suite
./scripts/verify-phase5-immich.sh

# Run acceptance verification with structured JSON output
./scripts/verify-phase5-immich.sh --json
```
