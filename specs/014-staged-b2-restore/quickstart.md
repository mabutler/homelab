# Quickstart & Validation Guide: Staged Backblaze B2 Disaster Recovery

**Feature**: `014-staged-b2-restore`  
**Target Host**: `fidelacchius` (`admin@192.168.4.57`)  
**Contracts**: [staged-restore-contract.md](./contracts/staged-restore-contract.md), [verification-contract.md](./contracts/verification-contract.md)

---

## 1. Prerequisites

1. **4 Bootstrap Credentials**:
   - `B2_ACCOUNT_ID`
   - `B2_ACCOUNT_KEY`
   - `RESTIC_REPOSITORY` (`b2:fidelacchius-backups:fidelacchius`)
   - `RESTIC_PASSWORD`
2. **Target Environment**:
   - Clean or existing Arch Linux installation on `fidelacchius` with `restic` installed (`sudo pacman -Sy --noconfirm restic`).

---

## 2. Full Staged Bare-Metal Disaster Recovery Workflow

### Stage 1: System Bootstrap & Secrets (`--stage config` / `--stage 1`)

Run Stage 1 on a clean OS installation **before** Docker or MergerFS are configured. This restores `/etc/homelab`, `/home/admin/.ssh`, `/home/admin/.gemini`, and `/home/admin/projects`, enforces `0600`/`0700` permissions, syncs `vault.yml` into the Ansible inventory, excludes `/mnt/storage`, and skips post-restore hooks.

**On Target Host (Bash)**:
```bash
sudo -E ./scripts/restore-from-b2.sh --stage config --target-dir / --force
```

**Or Remotely from Workstation (PowerShell)**:
```powershell
./scripts/restore-from-b2.ps1 -HostAddress 192.168.4.57 -User admin -Stage config -Force
```

---

### Inter-Stage: Full Platform Convergence via Ansible (`site.yml`)

With `/etc/homelab/vault.yml` synced to `ansible/inventory/group_vars/all/vault.yml` and SSH/GitHub keys restored, execute the master Ansible playbook to install Docker, configure networking/Caddy/Tailscale, mount the MergerFS pool at `/mnt/storage`, and start application systemd units:

```bash
sudo pacman -S --noconfirm ansible-core sqlite
cd /home/admin/projects/homelab2/ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --connection=local
```

---

### Stage 2: Bulk Data & Application Hook Restoration (`--stage data` / `--stage 2`)

Once `site.yml` has mounted `/mnt/storage` and started container runtimes, run Stage 2. This verifies `mountpoint -q /mnt/storage` (preventing root NVMe disk leakage), extracts `/opt/services` and `/mnt/storage/media/photos`, ensures container services are running, and executes `/etc/homelab/backup.d/*.sh post-restore` (`10-vaultwarden.sh`, `20-frigate.sh`, `30-immich.sh`):

**On Target Host (Bash)**:
```bash
sudo -E ./scripts/restore-from-b2.sh --stage data --target-dir / --force
```

**Or Remotely from Workstation (PowerShell)**:
```powershell
./scripts/restore-from-b2.ps1 -HostAddress 192.168.4.57 -User admin -Stage data -Force
```

---

## 3. Non-Destructive Validation Scenarios (Safe on Live Host)

### Scenario A: Validate Stage 1 & Stage 2 Dry-Run Filtering
```bash
set -a; source /etc/homelab/backup.env; set +a

# List Stage 1 candidate files (only /etc/homelab, .ssh, .gemini, projects; zero /mnt/storage)
sudo -E ./scripts/restore-from-b2.sh --stage config --dry-run

# List Stage 2 candidate files (only /opt/services and /mnt/storage/media/photos)
sudo -E ./scripts/restore-from-b2.sh --stage data --dry-run
```

### Scenario B: Validate Unmounted Storage Pool Protection (NVMe Leakage Guard)
```bash
set -a; source /etc/homelab/backup.env; set +a

# Attempt Stage 2 restore into a temporary directory where mnt/storage is not a mountpoint
sudo -E ./scripts/restore-from-b2.sh --stage data --target-dir /tmp/b2-unmounted-test --force
# Expected: Immediately aborts with exit code 1 and CRITICAL stderr message
```

### Scenario C: Run Automated Acceptance Verification Suite (`BK-001` – `BK-012`)
```bash
# Static syntax & lint checks
bash -n scripts/restore-from-b2.sh scripts/verify-phase5-backup.sh
shellcheck scripts/restore-from-b2.sh scripts/verify-phase5-backup.sh
ansible-lint ansible/playbooks/verify-phase5-backup.yml ansible/roles/backup/

# Live acceptance verification suite
sudo ./scripts/verify-phase5-backup.sh
sudo ./scripts/verify-phase5-backup.sh --json
```
