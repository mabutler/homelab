# Quickstart Validation Guide: System Identity & Backup Bucket Naming (Fidelacchius)

**Feature**: `010-fidelacchius-system-rename`  
**Date**: 2026-11-04  
**Status**: Ready for Implementation  

---

## Prerequisites

Before executing the validation scenarios, ensure:
1. Operator has administrative `sudo` access on the target host.
2. The legacy offline device (`100.109.1.87`, name `fidelacchius`) has been removed/deleted from the Tailscale Admin Console.
3. The Backblaze B2 bucket `fidelacchius-backups` exists or the B2 application credentials have permissions to create/write to it.
4. Python 3 and Ansible are installed locally or on the target host.

---

## Validation Scenarios

### Scenario 1: Verify Hostname & Local Resolution

**Objective**: Verify the system operating system reports `fidelacchius` and resolves properly via loopback.

```bash
# 1. Check static and transient hostname
hostnamectl status | grep "Static hostname: fidelacchius"
uname -n | grep "fidelacchius"

# 2. Check local hosts mapping
getent hosts fidelacchius
# Expected: 127.0.1.1 (or 127.0.0.1) fidelacchius.localdomain fidelacchius

# 3. Check shell prompt in new subshell
bash -i -c 'echo "Prompt host: $HOSTNAME"'
# Expected output: Prompt host: fidelacchius
```

**Expected Outcome**: All three checks pass with `fidelacchius`.

---

## Scenario 2: Verify Tailscale Node Identity & Funnel Routing

**Objective**: Ensure the node has claimed `fidelacchius` without numerical suffix and routes public Funnel ingress for Vaultwarden.

```bash
# 1. Query Tailscale node status
tailscale status --json | jq -r '.Self.HostName'
# Expected: fidelacchius (NOT fidelacchius-1)

tailscale status --json | jq -r '.Self.DNSName'
# Expected: fidelacchius.fable-mackarel.ts.net.

# 2. Query Funnel status
tailscale funnel status
# Expected: Displays active Funnel forwarding https://fidelacchius.fable-mackarel.ts.net -> 8088

# 3. Verify Vaultwarden environment configuration
grep "DOMAIN=" /opt/services/vaultwarden/.env
# Expected: DOMAIN=https://fidelacchius.fable-mackarel.ts.net

# 4. Verify HTTP health via Funnel endpoint
curl -fsSLI "https://fidelacchius.fable-mackarel.ts.net" | grep -E "HTTP/(1\.1|2) (200|302)"
```

**Expected Outcome**: Tailscale identity and Funnel route are cleanly registered as `fidelacchius.fable-mackarel.ts.net`.

---

## Scenario 3: Verify Backblaze B2 Repository & Restore Drill

**Objective**: Verify the new B2 bucket `fidelacchius-backups` is initialized, backup snapshots are written, and a non-destructive restore drill verifies 100% data integrity.

```bash
# 1. Verify backup environment file points to the official repository
grep "RESTIC_REPOSITORY=" /etc/homelab/backup.env
# Expected: RESTIC_REPOSITORY="b2:fidelacchius-backups:fidelacchius"

# 2. Test Restic connectivity and snapshot listing
source /etc/homelab/backup.env
restic -r "$RESTIC_REPOSITORY" snapshots

# 3. Trigger manual backup run
sudo /usr/local/bin/homelab-backup run

# 4. Perform non-destructive restore verification drill
rm -rf /tmp/b2-test-restore
sudo /usr/local/bin/restore-from-b2.sh \
  --target-dir /tmp/b2-test-restore \
  --include-path etc/homelab/vault.yml \
  --force

# 5. Assert data integrity via SHA256 checksum
ORIG_SUM=$(sha256sum /etc/homelab/vault.yml | awk '{print $1}')
REST_SUM=$(sha256sum /tmp/b2-test-restore/etc/homelab/vault.yml | awk '{print $1}')

if [ "$ORIG_SUM" = "$REST_SUM" ]; then
    echo "RESTORE DRILL VERIFICATION PASSED (Checksum: $ORIG_SUM)"
else
    echo "RESTORE DRILL VERIFICATION FAILED: Checksum mismatch" >&2
    exit 1
fi
```

**Expected Outcome**: Backup snapshot completes and the restored secret file matches the original SHA256 checksum.

---

## Scenario 4: Verify Ansible Inventory & Declarative Convergence

**Objective**: Verify Ansible inventory resolves host `fidelacchius` and loads its host variables cleanly.

```bash
cd ansible

# 1. Check inventory graph
ansible-inventory -i inventory/hosts.yml --graph
# Expected: Displays fidelacchius under homelab_nodes and arch_linux

# 2. Check host-specific variables lookup
ansible-inventory -i inventory/hosts.yml --host fidelacchius | jq '.snapraid_disks // .storage_group'
# Expected: Returns valid host variable definitions from host_vars/fidelacchius/

# 3. Dry-run site playbook verification
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --limit fidelacchius --check
```

**Expected Outcome**: Ansible evaluates `fidelacchius` cleanly with 0 unreachable hosts and 0 syntax or variable errors.

---

## Scenario 5: Run Automated Verification Suites

**Objective**: Execute the repository's automated test scripts to ensure all system acceptance gates pass.

```bash
# 1. Network & Overlay Verification
./scripts/verify-phase3.sh

# 2. Vaultwarden Ingress Verification
./scripts/verify-phase5-vaultwarden.sh

# 3. Backup System Verification
./scripts/verify-phase5-backup.sh
```

**Expected Outcome**: All automated assertion suites exit with status 0 and all tests `[PASS]`.
