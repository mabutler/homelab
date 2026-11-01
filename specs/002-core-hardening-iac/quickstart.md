# Quickstart & Verification Guide: Core Hardening & IaC

**Feature**: Core Hardening & Configuration Management Foundation  
**Branch**: `002-core-hardening-iac`  
**Date**: 2026-11-01  

This guide provides step-by-step instructions for operators to execute, test, and verify Phase 2 configuration management against the production host `admin@192.168.4.57`.

---

## 1. Prerequisites

Before executing Phase 2 convergence:
1. Target production host `192.168.4.57` is online, running Arch Linux, and reachable via SSH as `admin` using existing SSH key authentication.
2. The operator workstation has:
   - SSH client with identity key matching `admin@192.168.4.57`
   - Either:
     - Local Ansible installation (Linux/macOS/WSL)
     - OR PowerShell 7+ on Windows using the remote runner script (`scripts/apply-phase2.ps1`)
3. SOPS / age key file available if decrypting vaulted production secrets (`export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt`).

---

## 2. Environment Preparation

### Step 2.1: Verify Target Reachability
Run an initial ping and SSH connection check:
```bash
# Verify SSH key authentication
ssh -o BatchMode=yes admin@192.168.4.57 "echo 'Host reachable'; uname -a"
```
Expected output:
```text
Host reachable
Linux homelab 7.2.11-arch1-1 #1 SMP PREEMPT_DYNAMIC ... x86_64 GNU/Linux
```

### Step 2.2: Verify Inventory Target
Check `ansible/inventory/hosts.yml` to confirm target host configuration:
```yaml
all:
  children:
    homelab_nodes:
      hosts:
        homelab2:
          ansible_host: 192.168.4.57
          ansible_user: admin
          ansible_python_interpreter: /usr/bin/python3
```

---

## 3. Convergence Execution

### Step 3.1: Execute Site Convergence Playbook

#### Option A: Direct Push via Ansible (Linux/macOS/WSL)
```bash
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

#### Option B: Windows Operator Remoting (PowerShell)
```powershell
.\scripts\apply-phase2.ps1 -HostAddress 192.168.4.57 -User admin
```

#### Option C: Remote Runner (POSIX)
```bash
./scripts/apply-phase2.sh --host 192.168.4.57 --user admin
```

Expected output:
- All tasks complete successfully.
- `failed=0` on the summary line.

### Step 3.2: Verify Idempotency (Strict Zero Changes)
Immediately re-run the convergence command:
```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```
**Expected outcome**:
```text
PLAY RECAP *********************************************************************
homelab2                   : ok=24   changed=0    unreachable=0    failed=0
```
`changed=0` confirms strict idempotency (Constitution Principle II).

---

## 4. Acceptance Verification & Quality Gates

Run the automated verification suite against `192.168.4.57` to assert all Phase 2 operational gates:

```bash
# Run standalone verification script
./scripts/verify-phase2.sh --host 192.168.4.57 --user admin

# OR run the Ansible verification playbook
ansible-playbook -i inventory/hosts.yml playbooks/verify.yml
```

### Expected Verification Results:
1. **SSH Hardening Assertion**:
   - Password login attempt: `ssh -o PreferredAuthentications=password admin@192.168.4.57` -> `Permission denied (publickey)`.
   - Public key login: Succeeded in < 3 seconds.
2. **Sudoers Privilege Assertion**:
   - `ssh admin@192.168.4.57 "sudo -n true"` -> Exits 0 silently with no password prompt.
3. **Core Daemons Health Assertions**:
   - `chronyd`: active, NTP tracking established (`chronyc tracking`).
   - `smartd`: active, monitoring ATA/NVMe devices (`systemctl is-active smartd`).
   - `systemd-oomd`: active, memory pressure cgroup watching enabled (`oomctl`).
   - `journald`: active, storage persistent, disk usage within quota.
4. **Hardware Udev Rules**:
   - Rules at `/etc/udev/rules.d/99-homelab-peripherals.rules` parsed and valid.
5. **Backup & Secret Gate**:
   - `vault.sops.yml` committed to git in ciphertext form.
   - Out-of-band age key backup recorded in `docs/recovery/age-key-backup.md`.

Upon 100% pass, Phase 2 is complete on the production machine `192.168.4.57` and the host is ready for **Phase 3 (Network & Remote Access Overlay)**.
