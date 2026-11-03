# Contract: Antigravity CLI & Remote Control Daemon Management

**Contract Identifier**: `AG-DAEMON-V1`  
**Target Host**: `admin@192.168.4.57` (`homelab2`)  
**Operator User**: `admin`  

---

## 1. Binary Installation & System Path

### 1.1 Installation Specification
The Antigravity CLI (`agy`) binary must be installed under the unprivileged operator user:
- **Binary Target**: `/home/admin/.local/bin/agy` (mode `0755 admin:admin`)
- **System-wide Symlink**: `/usr/local/bin/agy` -> `/home/admin/.local/bin/agy`
- **Installation Method**: Official installer curl stream:
  ```bash
  curl -fsSL https://antigravity.google/cli/install.sh | bash
  ```
- **Idempotency Condition**: If `command -v agy` returns exit code 0 and `agy --version` succeeds, the installer curl invocation MUST be skipped.

---

## 2. Remote Control Background Daemon

### 2.1 Daemon Registration
The Remote Control daemon is registered using the official CLI subcommand:
```bash
agy remote-control start --name homelab2-target
```

### 2.2 Systemd Unit Specification
The command generates and registers a native systemd user unit:
- **Unit Path**: `/home/admin/.config/systemd/user/agy-remote-control.service`
- **Scope**: User service (`systemctl --user`)
- **Unit Properties**:
  - `Restart=always`
  - `RestartSec=5`
  - Process environment includes `HOME=/home/admin` and `PATH=/home/admin/.local/bin:/usr/local/bin:/usr/bin:/bin`

### 2.3 User Lingering (Persistent Execution at Boot)
To ensure the systemd user manager and daemon launch at system boot without requiring an interactive SSH session, systemd lingering MUST be enabled:
```bash
loginctl enable-linger admin
```
- **Validation**: `/var/lib/systemd/linger/admin` MUST exist.

---

## 3. Daemon Lifecycle & Health Interface

### 3.1 Control Commands
| Action | Shell Command |
|---|---|
| Start Daemon | `agy remote-control start --name homelab2-target` or `systemctl --user start agy-remote-control.service` |
| Stop Daemon | `agy remote-control stop` or `systemctl --user stop agy-remote-control.service` |
| Status Check | `agy remote-control status` or `systemctl --user is-active agy-remote-control.service` |
| View Logs | `journalctl --user -u agy-remote-control.service -n 50 --no-pager` |

### 3.2 Health Check Assertions
A healthy running instance must satisfy:
1. `systemctl --user is-active agy-remote-control.service` exits with code `0` (output: `active`).
2. `agy remote-control status` exits with code `0` and outputs instance registration details containing `homelab2-target`.
3. `/var/lib/systemd/linger/admin` exists, ensuring persistence across reboots.
