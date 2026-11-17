# Full Bare-Metal Disaster Recovery & Restore Runbook

**Target Node**: `fidelacchius` (`192.168.4.57` / `fidelacchius.fable-mackarel.ts.net`)  
**Repository**: `https://github.com/mabutler/homelab.git` (branch: `second_attempt`)  
**Offsite Backup Repository**: `b2:fidelacchius-backups:fidelacchius`

---

## 1. Prerequisites Before Starting

Before wiping the OS drive (`/dev/nvme0n1`), ensure you have:
1. **Arch Linux Live USB** booted in native **UEFI** mode with wired Ethernet connected.
2. **SSH Private Key** (`~/.ssh/id_ed25519`) on your workstation matching `secrets/id_ed25519.pub`.
3. **4 Bootstrap Credentials** (from your password vault / offline emergency sheet):
   - `B2_ACCOUNT_ID` (Backblaze B2 Key ID)
   - `B2_ACCOUNT_KEY` (Backblaze B2 Application Key)
   - `RESTIC_REPOSITORY` (`b2:fidelacchius-backups:fidelacchius`)
   - `RESTIC_PASSWORD` (Restic encryption passphrase)

> [!IMPORTANT]
> **Storage Safety**: The Phase 1 installer only formats `/dev/nvme0n1` (the OS/fast tier NVMe). Your MergerFS HDD data drives (`/dev/sda1`, `/dev/sdb1`) and SnapRAID parity drive (`/dev/sdc1`) are untouched during an OS reinstall, though `/mnt/storage/media/photos` (`library`, `upload`, `profile`) is also backed up to Backblaze B2.

---

## 2. Step-by-Step Full Restore Procedure

### Phase 1: Bare-Metal Arch Linux OS Installation (Live USB)

1. Boot the target hardware from the **Arch Linux Live USB**.
2. At the live console (or via SSH into the live environment), clone the repository and run the automated installer:
   ```bash
   git clone -b second_attempt https://github.com/mabutler/homelab.git /root/homelab2
   cd /root/homelab2

   ./scripts/install/install.sh \
     --disk /dev/nvme0n1 \
     --hostname fidelacchius \
     --timezone America/New_York \
     --user admin \
     --ssh-key ./secrets/id_ed25519.pub
   ```
3. When prompted, type `nvme0n1` to confirm formatting `/dev/nvme0n1`.
4. Once all 10 pre-reboot checks pass (`[SUCCESS] Installation complete!`), remove the USB drive and reboot:
   ```bash
   reboot
   ```

---

### Phase 2: Stage 1 - System Bootstrap & Secrets Restoration (`--stage config`)

Execute Stage 1 on the clean OS installation **before** Docker or MergerFS storage are configured. This extracts host configurations, secret environment files, SSH keys, Antigravity OAuth tokens, and repository files, enforces restrictive permissions, syncs `vault.yml` into the Ansible inventory, excludes `/mnt/storage`, and skips post-restore hooks.

1. SSH into the freshly booted system as `admin`:
   ```bash
   ssh admin@192.168.4.57
   ```
2. Install `restic` on the clean host:
   ```bash
   sudo pacman -Sy --noconfirm restic
   ```
3. Clone the repository to `/home/admin/projects/homelab2`:
   ```bash
   mkdir -p ~/projects
   git clone -b second_attempt https://github.com/mabutler/homelab.git ~/projects/homelab2
   ln -sfn /home/admin/projects/homelab2 ~/homelab2
   cd ~/projects/homelab2
   ```
4. Export the 4 Backblaze B2 bootstrap credentials and execute Stage 1 restoration:
   ```bash
   export B2_ACCOUNT_ID="<YOUR_B2_ACCOUNT_ID>"
   export B2_ACCOUNT_KEY="<YOUR_B2_ACCOUNT_KEY>"
   export RESTIC_REPOSITORY="b2:fidelacchius-backups:fidelacchius"
   export RESTIC_PASSWORD="<YOUR_RESTIC_PASSWORD>"

   # Execute Stage 1 extraction to root (or use --dry-run first to preview candidate files)
   sudo -E ./scripts/restore-from-b2.sh --stage config --target-dir / --force
   ```
   *(Or orchestrate remotely from a Windows workstation: `./scripts/restore-from-b2.ps1 -HostAddress 192.168.4.57 -User admin -Stage config -Force`)*

   **What Stage 1 accomplishes automatically**:
   - Restores `/etc/homelab/vault.yml`, `/etc/homelab/backup.env`, `/etc/homelab/monitoring.env` with `0600 root:root` permissions.
   - Synchronizes `/etc/homelab/vault.yml` directly to `~/projects/homelab2/ansible/inventory/group_vars/all/vault.yml` with mode `0600` and `admin` ownership.
   - Restores `/home/admin/.ssh` (`0700`, private keys `0600`, public keys `0644`), `/home/admin/.gemini` (`0700`, JSON files `0600`), and `/home/admin/projects` with `admin:users` ownership.
   - Strictly excludes `/mnt/storage` and skips post-restore database hooks.

---

### Phase 3: Platform Convergence via Ansible (`site.yml`)

With `/etc/homelab/vault.yml` synchronized and SSH/deploy keys restored, run the master Ansible playbook. This installs Docker, sets up nftables and Caddy, partitions/mounts the MergerFS storage pool at `/mnt/storage`, configures SnapRAID, and deploys systemd units:

1. Install `ansible-core` on the host:
   ```bash
   sudo pacman -S --noconfirm ansible-core
   cd ~/projects/homelab2/ansible
   ansible-galaxy collection install -r requirements.yml
   ```
2. Run the master `site.yml` playbook against localhost:
   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/site.yml --connection=local
   ```
   *(Alternatively, run modular apply scripts: `./scripts/apply-phase2.sh`, `./scripts/apply-phase3.sh`, `./scripts/apply-phase4.sh`, `./scripts/apply-phase5.sh`, `./scripts/apply-phase5-frigate.sh`, `./scripts/apply-phase5-immich.sh`, `./scripts/apply-phase7-antigravity.sh --confirm-target-ready`, `./scripts/apply-phase8-monitoring.sh`.)*

---

### Phase 4: Stage 2 - Bulk Data & Database Hook Restoration (`--stage data`)

Once `site.yml` has mounted the MergerFS storage pool at `/mnt/storage` and deployed container services, run Stage 2. This enforces an active mountpoint check to protect the root NVMe drive, extracts bulk application states and media, ensures Docker and application containers are started, and automatically executes all post-restore database hooks:

1. Execute Stage 2 restoration:
   ```bash
   cd ~/projects/homelab2
   sudo -E ./scripts/restore-from-b2.sh --stage data --target-dir / --force
   ```
   *(Or orchestrate remotely from a Windows workstation: `./scripts/restore-from-b2.ps1 -HostAddress 192.168.4.57 -User admin -Stage data -Force`)*

   **What Stage 2 accomplishes automatically**:
   - **Mountpoint Safety Assertion**: Validates `mountpoint -q /mnt/storage`. If unmounted, immediately aborts with exit code `1` and emits a `CRITICAL` error to prevent multi-hundred-gigabyte media leakage onto the root NVMe drive.
   - Restores `/opt/services` (Vaultwarden, Frigate, Immich configurations, compose files, and transactional database backups) and enforces `0700 1000:1000` / `0600` permissions.
   - Restores `/mnt/storage/media/photos` (`library`, `upload`, `profile`) and enforces `2775` permissions owned by `1000:1001` (`admin:storage`).
   - Ensures `docker.service` and application units (`vaultwarden.service`, `frigate.service`, `immich.service`) are active.
   - Automatically executes all post-restore database hooks in `/etc/homelab/backup.d/*.sh post-restore`:
     - `10-vaultwarden.sh`: Restores `data/db.sqlite3` from `backups/snapshot.sqlite3`.
     - `20-frigate.sh`: Restores `config/frigate.db` from `backups/snapshot.sqlite3`.
     - `30-immich.sh`: Imports transactional PostgreSQL dump into `immich_postgres` and restarts services.

---

### Phase 5: End-to-End Post-Restore Verification

Run the automated verification suites from `~/projects/homelab2` to confirm 100% platform health across all subsystems:

```bash
cd ~/projects/homelab2

# Phase 2: Base Hardening & Safeguards
./scripts/verify-phase2.sh --local

# Phase 3: Network, Tailscale, Firewall & Caddy Ingress
./scripts/verify-phase3.sh --local

# Phase 4: Storage Pooling (MergerFS) & SnapRAID
./scripts/verify-phase4.sh --local

# Phase 5: Applications & Backups (BK-001 through BK-012)
sudo ./scripts/verify-phase5-backup.sh
./scripts/verify-phase5-vaultwarden.sh --local
./scripts/verify-phase5-frigate.sh --local
./scripts/verify-phase5-immich.sh --local

# Phase 7: Antigravity Remote Control Daemon
./scripts/verify-phase7-antigravity.sh --local

# Phase 8: Monitoring, ntfy & Healthchecks.io
sudo ./scripts/verify-phase8-monitoring.sh
```

---

## 3. Related Pre-Written Documentation

- [Phase 1 Arch Linux Live USB Installer Guide](../scripts/install/README.md)
- [Phase 3 Network Disaster Recovery Procedure](disaster-recovery-phase3.md)
- [Operational Runbook (Antigravity & Immich)](operations.md)
- [SOPS Master Age Key Backup & Recovery](recovery/age-key-backup.md)
