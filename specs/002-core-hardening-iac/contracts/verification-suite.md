# Contract: Automated Verification Suite & Health Assertions

**Feature**: Core Hardening & Configuration Management Foundation  
**Branch**: `002-core-hardening-iac`  
**Date**: 2026-11-01  

This contract defines the test assertions, command interfaces, telemetry queries, and pass/fail thresholds enforced to declare Phase 2 complete against production machine `admin@192.168.4.57`.

---

## 1. Automated Verification CLI Interface

A standalone verification orchestrator script is provided at `scripts/verify-phase2.sh` and mirrored in the Ansible verification playbook `ansible/playbooks/verify.yml`.

### CLI Syntax:
```bash
# Execute full Phase 2 verification against production machine
./scripts/verify-phase2.sh --host 192.168.4.57 --user admin

# Via Ansible verification playbook
ansible-playbook -i inventory/hosts.yml playbooks/verify.yml
```

### Options:
- `-h, --host <IP|HOSTNAME>`: Target host to verify (default: `192.168.4.57` parsed from `ansible/inventory/hosts.yml`).
- `-u, --user <USERNAME>`: SSH user for test connection (default: `admin`).
- `-i, --identity <KEY_PATH>`: SSH identity file for authentication.
- `--skip-rate-limit-test`: Skip the intrusive connection rate-limit burst test.

---

## 2. Health Assertion Matrix

| Check ID | Target Component | Verification Command / Probe | Success Threshold | Failure Action |
|---|---|---|---|---|
| **CHK-01** | OpenSSH Hardening | `ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no admin@192.168.4.57` | Connection rejected (`Permission denied (publickey)`) | Critical: Lockout or vulnerability warning; abort |
| **CHK-02** | SSH Key Auth | `ssh -o PreferredAuthentications=publickey admin@192.168.4.57 true` | Exit 0 in < 3 seconds | Critical: Network/SSH failure |
| **CHK-03** | Sudo Privileges | `ssh admin@192.168.4.57 "sudo -n true"` | Exit 0 with zero output and no password prompt | Critical: Admin privilege failure |
| **CHK-04** | Time Sync (`chronyd`) | `ssh admin@192.168.4.57 "systemctl is-active chronyd && chronyc tracking"` | Status `active`; Stratum >= 1; Leap status `Normal`; Offset < 50ms | Warning / Error |
| **CHK-05** | Disk Health (`smartd`) | `ssh admin@192.168.4.57 "systemctl is-active smartd"` | Status `active`; Journal logs show active monitoring loop | Warning: Check unsupported drives |
| **CHK-06** | Memory Guard (`oomd`)| `ssh admin@192.168.4.57 "systemctl is-active systemd-oomd && oomctl"` | Status `active`; cgroup swap/pressure monitoring active | Error: systemd-oomd inactive |
| **CHK-07** | Logging Quotas | `ssh admin@192.168.4.57 "systemctl is-active systemd-journald && journalctl --disk-usage"` | Storage persistent; disk usage within quota (<= 2.0GB) | Error: Storage misconfigured |
| **CHK-08** | Peripheral Rules | `ssh admin@192.168.4.57 "udevadm test /sys/class/tty/tty0"` & rule syntax check | Udev rule syntax valid; symlink definitions present | Error: Udev rule syntax invalid |
| **CHK-09** | Idempotency | `ansible-playbook playbooks/site.yml` | Output reports `changed=0`, `failed=0` | Error: Configuration drift detected |
| **CHK-10** | Vault Backup Posture| Git status check + out-of-band key doc | Encrypted vault tracked in git; master age key backup verified | Error: Uncommitted secrets or missing backup |

---

## 3. Exit Codes

- `0`: All assertions passed (100% compliance). Phase 2 is declared converged on `192.168.4.57` and ready for Phase 3.
- `1`: Non-critical warning or diagnostic threshold breach (e.g. clock still slewing, non-SMART drive ignored).
- `2`: Critical assertion failed (SSH password accepted, sudo requires password, core daemon dead, idempotency broken).
