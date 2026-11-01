# Phase 0: Research & Technical Decisions

**Feature**: Core Hardening & Configuration Management Foundation  
**Branch**: `002-core-hardening-iac`  
**Date**: 2026-11-01  

This document captures the technical evaluations, architectural decisions, and trade-offs for implementing Phase 2 of the `homelab2` platform on the production target machine `admin@192.168.4.57` in accordance with the [homelab2 Constitution](file:///C:/Users/micro/projects/homelab2/.specify/memory/constitution.md).

---

## 1. Production Machine Profile & Connectivity (`admin@192.168.4.57`)

### Decision
Target the production bare-metal host at IPv4 address `192.168.4.57`, connecting as `admin` using existing pre-authenticated SSH public keys and passwordless `sudo`.

### Findings from Live Target Inspection:
- **Operating System**: Arch Linux x86_64 (`Linux homelab 7.2.11-arch1-1`)
- **Python Runtime**: Python 3.14.9 (`/usr/bin/python3`)
- **Package Manager**: Pacman present (`/usr/bin/pacman`)
- **User & Privileges**: User `admin` is active, authorized SSH keys allow instant connection without interactive passwords, and `sudo -n true` succeeds.
- **Network Interface**: Local LAN subnet `192.168.4.0/24`.

### Rationale
- Target host has successfully completed Phase 1 bootstrap and is fully responsive.
- Python 3 is already installed, satisfying Ansible's target runtime requirement without needing a bootstrap wrapper.
- Key authentication is operational, ensuring non-interactive automation works immediately.

---

## 2. Configuration Management Framework & Orchestration Flow

### Decision
Deploy **Ansible** (2.15+ / core 2.16+) as the primary configuration management engine organized under an `ansible/` root directory in the repository:
```text
ansible/
├── ansible.cfg
├── inventory/
│   ├── hosts.yml (ansible_host: 192.168.4.57, ansible_user: admin)
│   ├── group_vars/
│   │   ├── all/
│   │   │   ├── vars.yml
│   │   │   └── vault.sops.yml
│   └── host_vars/
├── roles/
│   ├── common_packages/
│   ├── admin_user/
│   ├── ssh_hardening/
│   ├── time_sync/
│   ├── disk_health/
│   ├── system_safeguards/
│   └── udev_rules/
├── playbooks/
│   ├── site.yml
│   ├── harden.yml
│   └── verify.yml
└── requirements.yml
```

### Orchestration Mechanism:
Because operators may manage the infrastructure from diverse workstations (including Windows workstations without native Ansible CLI installation):
1. **Push Orchestration (Standard Controller)**: If the operator workstation is Linux/macOS/WSL with Ansible installed, run standard push execution:
   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/site.yml
   ```
2. **Cross-Platform Remote Runner (`scripts/apply-phase2.ps1` & `scripts/apply-phase2.sh`)**:
   Provides an automated mechanism that transfers `ansible/` via SSH/SFTP to the production machine (`admin@192.168.4.57`), ensures `ansible-core` is available (via pacman if needed), and executes the playbook locally on the host against `localhost` with Ansible local connection. This guarantees 100% platform-agnostic execution without forcing Windows operators to maintain complex local Ansible installations.

### Rationale
- Ansible requires no background daemons on target hosts (agentless over SSH), directly leveraging the Python 3 runtime and OpenSSH server on `192.168.4.57`.
- Clear separation into modular roles aligns strictly with Constitution Principle VI (Modular & Decoupled Architecture).
- The dual-path orchestration guarantees anyone on the local network with SSH key access can converge the machine.

### Alternatives Considered
- **OpenTofu/Terraform with remote-exec**: Awkward and non-idiomatic for bare-metal OS configuration and systemd service management.
- **Pure Shell Scripts (`scripts/configure/*.sh`)**: Boils down to imperative scripting; Ansible provides declarative idempotency and built-in change detection.
- **SaltStack / Puppet**: Introduces permanent background daemons, violating the Minimalist Footprint standard.

---

## 3. Remote Access Hardening & Anti-Lockout Safeguards

### Decision
Harden SSH and remote access while strictly protecting ongoing operator access to `admin@192.168.4.57`:
1. **Drop-in OpenSSH Configuration**: Place a declarative hardening drop-in file at `/etc/ssh/sshd_config.d/10-hardening.conf`:
   - `PasswordAuthentication no`
   - `PermitRootLogin no`
   - `PubkeyAuthentication yes`
   - `KbdInteractiveAuthentication no`
   - `X11Forwarding no`
   - `MaxAuthTries 3`
   - `AuthenticationMethods publickey`
   - Modern cryptographic ciphers (`chacha20-poly1305@openssh.com`, `aes256-gcm@openssh.com`)
2. **Anti-Lockout Validation**:
   - The drop-in template task MUST use `validate: '/usr/bin/sshd -t -f %s'` to guarantee syntax correctness before saving.
   - The administrative user role MUST ensure the operator's existing authorized public key is preserved in `/home/admin/.ssh/authorized_keys`.
3. **Fail2ban Subnet Whitelist**:
   - Configure `/etc/fail2ban/jail.local` with `backend = systemd`, `maxretry = 3`, `findtime = 10m`, `bantime = 1h`.
   - **Crucial Safeguard**: `ignoreip` MUST include `127.0.0.1/8` and the operator subnet `192.168.4.0/24` to prevent automated tests or accidental authentication retries from banning the management workstation.

### Rationale
- Completely eliminates credential brute-forcing while eliminating operator lockout risk.
- Drop-ins avoid modifying package-managed `/etc/ssh/sshd_config`, preventing pacnew conflicts on Arch Linux updates.

---

## 4. Secrets Management & SOPS / Age Encryption Pipeline

### Decision
Standardize on **SOPS** utilizing **age asymmetric encryption keys** (`age1...`), integrating with Ansible via the `community.sops` collection (`community.sops.load_vars`).

Secret files are stored with the naming pattern `vault.sops.yml` under `ansible/inventory/group_vars/all/`. In version control, all parameter values are encrypted ciphertext while keys remain plaintext for git-diff readability.

For environments where the production age private key is configured, `SOPS_AGE_KEY_FILE` points to the private age key file. If operating during initial setup where dummy vault secrets are used, playbooks gracefully handle key discovery and secret substitution.

### Rationale
- Strictly enforces Constitution Principle IV (Zero Cleartext Secrets).
- Age is modern, minimal, cryptographic state-of-the-art (Curve25519, ChaCha20-Poly1305) with concise keys, avoiding PGP/GPG complexity.
- SOPS preserves YAML key readability in git diffs while keeping values encrypted.

---

## 5. Core Operational Daemons & Telemetry Strategy

### Decision
Deploy and configure four core operational services:
1. **Time Synchronization (`chrony`)**: Configured with upstream pools (`2.arch.pool.ntp.org iburst`) and `rtcsync` enabled.
2. **Drive Diagnostics (`smartd`)**: Configured with `DEVICESCAN -a -o on -S on -s (S/../.././02|L/../../6/03) -H -C 197+ -U 198+ -W 4,45,55` to continuously monitor ATA/NVMe drive health.
3. **Memory Safeguards (`systemd-oomd`)**: Configured with `SwapUsedLimit=90%` and `DefaultMemoryPressureLimit=80%` to protect against kernel lockups.
4. **Log Retention (`systemd-journald`)**: Persistent journal logging bounded to 2.0 GiB (`SystemMaxUse=2G`).

### Rationale
- Directly fulfills FR-007 through FR-011 and Acceptance Scenarios.
- Conforms to Constitution Principle III: Phase 2 local telemetry assertions verify these daemons are active and healthy.

---

## 6. Persistent Peripheral Symlinks (udev)

### Decision
Deploy `/etc/udev/rules.d/99-homelab-peripherals.rules` establishing persistent, non-conflicting symlinks:
- Z-Wave USB Controller: Symlink `/dev/zwave`, group `uucp`, mode `0660`.
- Google Coral TPU: Group `uucp`, mode `0660`.
- `/dev/uinput`: Group `input`, mode `0660`.

### Rationale
- Guarantees future container stacks in Phase 5 can access radio dongles and hardware accelerators by persistent predictable paths.
- Rules are non-blocking: if physical dongles are not currently inserted into `192.168.4.57`, udev rule compilation and reload succeeds without error.
