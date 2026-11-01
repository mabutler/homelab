# Data Model: Core Hardening & Configuration Management Foundation

**Feature**: Core Hardening & Configuration Management Foundation  
**Branch**: `002-core-hardening-iac`  
**Date**: 2026-11-01  

This document defines the core logical and configuration entities, their attributes, validation constraints, and lifecycle state transitions for Phase 2 of `homelab2`, targeting production machine `admin@192.168.4.57`.

---

## 1. Entity Overview & Relationships

```mermaid
erDiagram
    HOST_INVENTORY ||--|{ ADMINISTRATIVE_IDENTITY : defines
    HOST_INVENTORY ||--|| ENCRYPTED_SECRET_VAULT : references
    HOST_INVENTORY ||--|{ SYSTEM_DIAGNOSTIC_SERVICE : configures
    HOST_INVENTORY ||--|{ PERIPHERAL_HARDWARE_RULE : applies
    HOST_INVENTORY ||--|| SSH_HARDENING_POLICY : enforces
    HOST_INVENTORY ||--|| FAIL2BAN_INTRUSION_POLICY : enforces

    HOST_INVENTORY {
        string name PK
        string ansible_host
        string ansible_user
        int ansible_port
        string ansible_python_interpreter
        string connection_mode
    }

    ADMINISTRATIVE_IDENTITY {
        string username PK
        string shell
        string[] groups
        string[] authorized_keys
        boolean passwordless_sudo
    }

    ENCRYPTED_SECRET_VAULT {
        string file_path PK
        string encryption_type
        string[] recipient_age_keys
        map encrypted_variables
        timestamp last_modified
    }

    SSH_HARDENING_POLICY {
        int port
        boolean permit_root_login
        boolean password_authentication
        boolean pubkey_authentication
        string[] ciphers
        int max_auth_tries
    }

    FAIL2BAN_INTRUSION_POLICY {
        string backend
        int maxretry
        string findtime
        string bantime
        string[] ignoreip
    }

    SYSTEM_DIAGNOSTIC_SERVICE {
        string service_name PK
        string daemon_binary
        string config_path
        string[] target_metrics
        string desired_state
    }

    PERIPHERAL_HARDWARE_RULE {
        string rule_name PK
        string subsystem
        string vendor_id
        string product_id
        string symlink_target
        string group_owner
        string file_mode
    }
```

---

## 2. Entity Specifications

### 2.1 Host Inventory (`HostInventory`)
Represents the managed production node, connection parameters, variable scopes, and target architecture.

- **Attributes**:
  - `name`: string (`homelab2`)
  - `ansible_host`: string (`192.168.4.57`)
  - `ansible_user`: string (`admin`)
  - `ansible_port`: integer (`22`)
  - `ansible_python_interpreter`: string (`/usr/bin/python3`)
  - `connection_mode`: enum (`ssh`, `local`)
  - `group_memberships`: list of strings (`[homelab_nodes, arch_linux]`)
- **Validation Rules**:
  - `ansible_host` must be reachable over SSH.
  - Target host must run Python 3.10+ (target has 3.14.9).
  - Target host must have passwordless `sudo` privileges configured for `ansible_user`.
- **Lifecycle States**:
  - `Bootstrapped` -> `Reachable` -> `Hardening Applied` -> `Converged & Verified`.

---

### 2.2 Encrypted Secret Vault (`EncryptedSecretVault`)
Represents sensitive operational parameters (tokens, credentials, passphrases) encrypted at rest using asymmetric public key cryptography via SOPS.

- **Attributes**:
  - `file_path`: string (`ansible/inventory/group_vars/all/vault.sops.yml`)
  - `format`: enum (`yaml`, `json`)
  - `sops_metadata`:
    - `age_recipients`: list of age public keys (`age1...`)
    - `last_modified`: ISO8601 timestamp
    - `version`: string (SOPS version)
    - `mac`: string (cryptographic message authentication code)
  - `payload`: dictionary of key-value pairs (ciphertext at rest, plaintext in memory during playbook execution)
- **Validation Rules**:
  - Unencrypted files matching `*.sops.yml` MUST NEVER be committed to git.
  - Secret payloads must pass MAC integrity checks upon decryption.

---

### 2.3 Administrative Identity (`AdministrativeIdentity`)
Represents the operator account authorized to administer the host.

- **Attributes**:
  - `username`: string (`admin`)
  - `shell`: string (`/bin/bash`)
  - `groups`: list of strings (`[wheel, uucp, input, video]`)
  - `authorized_keys`: list of OpenSSH public key strings
  - `passwordless_sudo`: boolean (`true`)
- **Validation Rules**:
  - `wheel` group drop-in MUST be verified with `/usr/sbin/visudo -cf %s` before application.
  - File permissions for `/etc/sudoers.d/*` drop-ins MUST be `0440`.
  - Operator's existing public key MUST remain in `authorized_keys`.

---

### 2.4 SSH Hardening & Intrusion Prevention (`SshHardeningPolicy` & `Fail2banPolicy`)
Represents OpenSSH daemon drop-in settings and fail2ban intrusion detection rules.

- **Attributes (SSH)**:
  - `config_path`: `/etc/ssh/sshd_config.d/10-hardening.conf`
  - `port`: integer (`22`)
  - `permit_root_login`: boolean (`false`)
  - `password_authentication`: boolean (`false`)
  - `pubkey_authentication`: boolean (`true`)
  - `ciphers`: list (`[chacha20-poly1305@openssh.com, aes256-gcm@openssh.com, aes128-gcm@openssh.com]`)
- **Attributes (Fail2ban)**:
  - `config_path`: `/etc/fail2ban/jail.local`
  - `backend`: string (`systemd`)
  - `maxretry`: integer (`3`)
  - `findtime`: string (`10m`)
  - `bantime`: string (`1h`)
  - `ignoreip`: list of CIDRs (`['127.0.0.1/8', '192.168.4.0/24']`)
- **Validation Rules**:
  - OpenSSH configuration drop-in MUST pass `/usr/bin/sshd -t -f %s` syntax check before reload.
  - Subnet `192.168.4.0/24` MUST be included in `ignoreip` to prevent operator lockout.

---

### 2.5 System Diagnostic Services (`SystemDiagnosticService`)
Represents background services for time synchronization, disk health, memory pressure, and logging.

| Service Name | Package | Config Path | Systemd Unit | Validation Command |
|---|---|---|---|---|
| `chrony` | `chrony` | `/etc/chrony.conf` | `chronyd.service` | `chronyc tracking` |
| `smartmontools` | `smartmontools` | `/etc/smartd.conf` | `smartd.service` | `systemctl is-active smartd` |
| `systemd-oomd` | `systemd` | `/etc/systemd/oomd.conf` | `systemd-oomd.service` | `oomctl` |
| `journald` | `systemd` | `/etc/systemd/journald.conf.d/00-retention.conf` | `systemd-journald.service` | `journalctl --disk-usage` |

---

### 2.6 Peripheral Hardware Rules (`PeripheralHardwareRule`)
Represents persistent device symlinks and access permissions managed via udev.

- **Attributes**:
  - `config_path`: `/etc/udev/rules.d/99-homelab-peripherals.rules`
  - Target rules:
    - Z-Wave USB Stick (`SUBSYSTEM=="tty"`, symlink `/dev/zwave`, group `uucp`, mode `0660`)
    - Google Coral TPU (`SUBSYSTEM=="usb"`, group `uucp`, mode `0660`)
    - Uinput (`KERNEL=="uinput"`, group `input`, mode `0660`)
- **Validation Rules**:
  - Rules file MUST be syntactically valid and reload cleanly with `udevadm control --reload-rules && udevadm trigger`.
  - Non-presence of physical hardware dongles MUST NOT fail execution.
