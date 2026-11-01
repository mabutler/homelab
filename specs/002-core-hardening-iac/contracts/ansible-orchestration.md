# Contract: Ansible Orchestration & CLI Interface

**Feature**: Core Hardening & Configuration Management Foundation  
**Branch**: `002-core-hardening-iac`  
**Date**: 2026-11-01  

This contract defines the execution commands, playbook targets, tags, environment variables, and exit codes for operating Ansible against the production host `admin@192.168.4.57` within the `homelab2` platform.

---

## 1. Directory Root & Configuration File

Ansible operations execute from the `ansible/` directory in the repository root.

```text
ansible/
├── ansible.cfg
├── inventory/
│   ├── hosts.yml
│   └── group_vars/
│       └── all/
│           ├── vars.yml
│           └── vault.sops.yml
├── playbooks/
│   ├── site.yml
│   ├── harden.yml
│   └── verify.yml
└── roles/
```

### 1.1 `inventory/hosts.yml` Target Definition

```yaml
---
all:
  children:
    homelab_nodes:
      hosts:
        homelab2:
          ansible_host: 192.168.4.57
          ansible_user: admin
          ansible_python_interpreter: /usr/bin/python3
```

### 1.2 `ansible.cfg` Standard Parameters

```ini
[defaults]
inventory = inventory/hosts.yml
roles_path = roles
remote_user = admin
host_key_checking = True
retry_files_enabled = False
stdout_callback = yaml
bin_ansible_callbacks = True
interpreter_python = auto_silent

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False

[ssh_connection]
pipelining = True
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=accept-new
```

---

## 2. Command-Line Invocations

### 2.1 Complete Convergence (Full Site)

Applies all base roles, hardening configurations, diagnostic services, and peripheral mappings against `homelab2` (`192.168.4.57`).

```bash
# Push execution from Ansible controller
ansible-playbook -i inventory/hosts.yml playbooks/site.yml

# Or cross-platform execution runner from repository root
./scripts/apply-phase2.sh --host 192.168.4.57
# or on Windows PowerShell:
.\scripts\apply-phase2.ps1 -HostAddress 192.168.4.57
```

### 2.2 Targeted Execution via Tags

Operators can target specific subsystems without running the full configuration:

```bash
# Apply only SSH hardening and sudoers policies
ansible-playbook playbooks/site.yml --tags "security,ssh"

# Apply only diagnostic services (chrony, smartd, systemd-oomd)
ansible-playbook playbooks/site.yml --tags "diagnostics"

# Apply only udev rules
ansible-playbook playbooks/site.yml --tags "udev"
```

### Supported Tags:
| Tag | Scope |
|---|---|
| `security` | SSH hardening, fail2ban, sudoers privilege policies |
| `ssh` | SSH configuration and rate limiting |
| `sudo` | Wheel group sudoers drop-in |
| `diagnostics` | Chrony time sync, smartd disk monitoring, systemd-oomd |
| `udev` | Hardware peripheral symlink rules |
| `journald` | Persistent system logging and size quotas |

### 2.3 Syntax Check & Dry Run (Check Mode)

```bash
# Syntax validation (used in CI/pre-commit)
ansible-playbook --syntax-check playbooks/site.yml

# Idempotency dry run (predict changes without applying)
ansible-playbook --check --diff playbooks/site.yml
```

---

## 3. Environment Variables & Credentials

| Variable | Description | Required / Default |
|---|---|---|
| `SOPS_AGE_KEY_FILE` | Path to private age key file used to decrypt vault variables | Defaults to `~/.config/sops/age/keys.txt` |
| `ANSIBLE_INVENTORY` | Override path to target inventory file | Defaults to `inventory/hosts.yml` |

---

## 4. Exit Codes

| Exit Code | Meaning | Operational Handling |
|---|---|---|
| `0` | Success | All tasks succeeded or reported "ok" (converged). Strict idempotency requires 0 "changed" on repeated runs. |
| `1` | General Error | Inventory parsing error, syntax error, or command syntax issue. |
| `2` | Host Failure | One or more tasks failed on the target host. Ansible halts execution for failed host. |
| `4` | Host Unreachable | Target host `192.168.4.57` is not reachable over SSH network or connection refused. |
| `99` | User Interrupt | Playbook run interrupted by operator (Ctrl+C). |
