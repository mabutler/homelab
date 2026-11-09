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

### Phase 2: Restore State & Secrets from Backblaze B2

1. SSH into the freshly booted system as `admin`:
   ```bash
   ssh admin@192.168.4.57
   ```
2. Install `restic` and `sqlite` so the restore script and hooks can run prior to full Ansible convergence:
   ```bash
   sudo pacman -Sy --noconfirm restic sqlite
   ```
3. Clone the repository to `/home/admin/projects/homelab2`:
   ```bash
   mkdir -p ~/projects
   git clone -b second_attempt https://github.com/mabutler/homelab.git ~/projects/homelab2
   ln -sfn /home/admin/projects/homelab2 ~/homelab2
   cd ~/projects/homelab2
   ```
4. Export the 4 Backblaze B2 + Restic bootstrap credentials and execute the full restore to `/`:
   ```bash
   export B2_ACCOUNT_ID="<YOUR_B2_ACCOUNT_ID>"
   export B2_ACCOUNT_KEY="<YOUR_B2_ACCOUNT_KEY>"
   export RESTIC_REPOSITORY="b2:fidelacchius-backups:fidelacchius"
   export RESTIC_PASSWORD="<YOUR_RESTIC_PASSWORD>"

   sudo -E ./scripts/restore-from-b2.sh --target-dir / --force
   ```
   **What this restores automatically**:
   - `/etc/homelab/vault.yml` (and syncs it to `~/projects/homelab2/ansible/inventory/group_vars/all/vault.yml`)
   - `/etc/homelab/monitoring.env` and `/var/lib/homelab/monitoring/checks.json`
   - `/opt/services/vaultwarden` (and restores `data/db.sqlite3` from `backups/snapshot.sqlite3` via `10-vaultwarden.sh post-restore`)
   - `/opt/services/frigate` (and restores `config/frigate.db` from `backups/snapshot.sqlite3` via `20-frigate.sh post-restore`)
   - `/opt/services/immich/backups/immich_db_backup.dump`
   - `/mnt/storage/media/photos` (`library`, `upload`, `profile`)
   - `/home/admin/.gemini/*`, `/home/admin/.config/antigravity/*`, `/home/admin/.config/sops/age/keys.txt`, and `/home/admin/.ssh/id_ed25519_github*`

5. Fix ownership on restored `/home/admin` files:
   ```bash
   sudo chown -R admin:users /home/admin/.gemini /home/admin/.config /home/admin/.ssh /home/admin/projects
   chmod 700 /home/admin/.ssh /home/admin/.gemini
   chmod 600 /home/admin/.ssh/id_ed25519_github
   ```

---

### Phase 3: Full Platform Convergence via Ansible (`site.yml`)

1. Install `ansible-core` on the host (if running convergence locally on `fidelacchius`):
   ```bash
   sudo pacman -S --noconfirm ansible-core
   cd ~/projects/homelab2/ansible
   ansible-galaxy collection install -r requirements.yml
   ```
2. Run the master `site.yml` playbook against localhost to converge all system hardening, networking (Tailscale, nftables, Caddy), storage mounts (MergerFS, SnapRAID), Docker stacks (Vaultwarden, Frigate, Immich), Backup timers, Antigravity daemon, and Monitoring:
   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/site.yml --connection=local
   ```
   *(Alternatively, run the phase apply scripts from your workstation or host: `./scripts/apply-phase2.sh`, `./scripts/apply-phase3.sh`, `./scripts/apply-phase4.sh`, `./scripts/apply-phase5.sh`, `./scripts/apply-phase5-frigate.sh`, `./scripts/apply-phase5-immich.sh`, `./scripts/apply-phase7-antigravity.sh --confirm-target-ready`, `./scripts/apply-phase8-monitoring.sh`.)*

---

### Phase 4: Restore Immich PostgreSQL Database

Once `site.yml` has started the Docker daemon and the `immich.service` stack (`immich_postgres` container is running), restore the transactional PostgreSQL dump:

```bash
# Ensure Immich containers are up
sudo systemctl start immich.service

# Restore PostgreSQL database from /opt/services/immich/backups/immich_db_backup.dump
sudo /etc/homelab/backup.d/30-immich.sh post-restore

# Restart Immich server to reconnect cleanly to the restored database
sudo systemctl restart immich.service
```

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

# Phase 5: Applications & Backups
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
- [Phase 5 Backblaze B2 Backup & Restore Quickstart](../specs/006-backblaze-backup-restore/quickstart.md)
- [Operational Runbook (Antigravity & Immich)](operations.md)
- [SOPS Master Age Key Backup & Recovery](recovery/age-key-backup.md)
