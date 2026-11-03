# Quickstart & Operational Validation Guide: Centralized Backblaze B2 Backup & Disaster Recovery

**Feature**: `006-backblaze-backup-restore`  
**Target Node**: `admin@192.168.4.57` (`homelab2`)  

---

## 1. Prerequisites

1. **Backblaze B2 Bucket**:
   - Create a Backblaze B2 private bucket (e.g. `homelab2-backup`).
   - Create an Application Key with read/write/delete permissions targeting that bucket.
   - Note the **Key ID** (`vault_b2_account_id`) and **Application Key** (`vault_b2_account_key`).
2. **Local Configuration**:
   - Ensure `ansible/inventory/group_vars/all/vault.yml` contains:
     ```yaml
     vault_b2_account_id: "00xxxxxxxxxxxxxxx"
     vault_b2_account_key: "K00xxxxxxxxxxxxxxxxxxxx"
     vault_restic_repository: "b2:homelab2-backup:homelab2"
     vault_restic_password: "a-very-strong-restic-encryption-password"
     ```

---

## 2. Deployment & Convergence

Run Phase 5 deployment from your workstation to configure Restic, initialize the B2 repository, install the backup runner, set up hooks, and enable systemd timers:

```powershell
# From repo root on workstation:
./scripts/apply-phase5.ps1 -HostAddress 192.168.4.57 -User admin
```

Or directly via SSH on the target server:
```bash
sudo ./scripts/apply-phase5.sh
```

---

## 3. End-to-End Validation Scenarios

### Scenario 1: Initial Backup Execution & Integrity Verification
Trigger the backup runner on-demand to execute pre-backup hooks, upload encrypted snapshots to Backblaze B2, and prune retention:

```bash
# SSH into homelab2
ssh admin@192.168.4.57

# Trigger backup
sudo /usr/local/bin/homelab-backup run
```

**Expected Outcome**:
1. Pre-backup hook `/etc/homelab/backup.d/10-vaultwarden.sh` executes `VACUUM INTO` and passes `PRAGMA integrity_check; == ok`.
2. Restic transmits snapshot to Backblaze B2 with status `snapshot <ID> saved`.
3. Snapshot includes `/etc/homelab/vault.yml` and `/opt/services/vaultwarden/backups/snapshot.sqlite3`.
4. Snapshot excludes live `/opt/services/vaultwarden/data/db.sqlite3`.
5. Exit code is `0`.

---

### Scenario 2: Listing Snapshots in Backblaze B2
Inspect the offsite snapshots catalog:

```bash
sudo /usr/local/bin/homelab-backup snapshots
```

**Expected Outcome**:
Table displaying Snapshot ID, Date, Host (`homelab2`), and Tags (`homelab2`, `daily`).

---

### Scenario 3: Automated Verification Suite
Run the 8 automated acceptance assertions:

```powershell
# From workstation:
./scripts/verify-phase5-backup.ps1 -TargetHost 192.168.4.57 -User admin
```

Or on the target host:
```bash
sudo ./scripts/verify-phase5-backup.sh
```

**Expected Outcome**:
All 8 checks pass (`[PASS] BK-001` through `[PASS] BK-008`).

---

### Scenario 4: Non-Destructive Disaster Recovery Rehearsal
Verify that `scripts/restore-from-b2.sh` can authenticate using only the 4 bootstrap credentials and recover secrets and application data to an isolated test directory:

```bash
# Run restore rehearsal to a temporary directory
sudo ./scripts/restore-from-b2.sh \
  --account-id "00xxxxxxxxxxxxxxx" \
  --account-key "K00xxxxxxxxxxxxxxxxxxxx" \
  --repository "b2:homelab2-backup:homelab2" \
  --password "a-very-strong-restic-encryption-password" \
  --target-dir "/tmp/b2-test-restore" \
  --force
```

**Validation**:
```bash
# Compare restored vault.yml checksum with active host secret
sha256sum /etc/homelab/vault.yml /tmp/b2-test-restore/etc/homelab/vault.yml

# Check restored Vaultwarden snapshot integrity
sqlite3 /tmp/b2-test-restore/opt/services/vaultwarden/backups/snapshot.sqlite3 "PRAGMA integrity_check;"
```

**Expected Outcome**:
1. Checksums match identically.
2. SQLite integrity check returns `ok`.
3. Test directory clean up: `rm -rf /tmp/b2-test-restore`.

---

### Scenario 5: Full Node Disaster Recovery (Bare Metal Simulation)
If the server's drive is wiped or hardware replaced:

1. Perform minimal base OS installation (Arch Linux or ISO boot).
2. Clone repository:
   ```bash
   git clone https://github.com/myorg/homelab2.git /opt/homelab2
   cd /opt/homelab2
   ```
3. Execute automated restore:
   ```bash
   export B2_ACCOUNT_ID="00xxxxxxxxxxxxxxx"
   export B2_ACCOUNT_KEY="K00xxxxxxxxxxxxxxxxxxxx"
   export RESTIC_REPOSITORY="b2:homelab2-backup:homelab2"
   export RESTIC_PASSWORD="a-very-strong-restic-encryption-password"
   
   sudo ./scripts/restore-from-b2.sh --force
   ```
4. Run deployment playbook:
   ```bash
   sudo ./scripts/apply-phase5.sh
   ```

**Expected Outcome**:
Host secrets, Vaultwarden database, encryption keys, and Caddy certificates are fully restored. Containers start, and `scripts/verify-phase5-vaultwarden.sh` reports 100% health checks passing.
