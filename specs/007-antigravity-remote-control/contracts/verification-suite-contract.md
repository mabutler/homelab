# Contract: Automated Antigravity & Remote Control Verification Suite

**Contract Identifier**: `AG-VERIFICATION-V1`  
**Test Runners**: `scripts/verify-phase7-antigravity.sh`, `scripts/verify-phase7-antigravity.ps1`, `ansible/playbooks/verify-phase7-antigravity.yml`  
**Target Host**: `admin@192.168.4.57` (`homelab2`)  

---

## 1. Automated Acceptance Assertions

The verification suite executes 8 automated checks across installation integrity, systemd service state, lingering persistence, autonomous settings, git workspace readiness, backup coverage, and version control hygiene.

| # | Check Name | Target / Command | Pass Criteria | Constitutional Rationale |
|---|---|---|---|---|
| **AG-001** | Antigravity CLI Binary Available | `command -v agy && agy --version` | Exit code 0, binary present in PATH and executable | Principle I |
| **AG-002** | User Lingering Enabled | `test -f /var/lib/systemd/linger/admin` | Exit code 0, linger marker exists for `admin` | Principle I & II |
| **AG-003** | Remote Control Service Active | `systemctl --user is-active agy-remote-control.service` | Exit code 0, reports `active` | Principle III |
| **AG-004** | Remote Control Status & Instance Registered | `agy remote-control status` | Exit code 0, displays instance name `homelab2-target` | Principle III |
| **AG-005** | Autonomous Settings & Perms Validated | `jq -e '.toolPermission == "always-proceed" and .agentMode == "auto"' /home/admin/.gemini/antigravity-cli/settings.json` | Exit code 0, JSON fields match autonomous spec; mode is `0600 admin:admin` | Principle I & IV |
| **AG-006** | Host Git Workspace & Worktrees Ready | `git -C /home/admin/homelab2 rev-parse --is-inside-work-tree && git -C /home/admin/homelab2 worktree list` | Exit code 0, valid git repository with worktree support | Principle I & VI |
| **AG-007** | Backup Registration Validated | `grep -F '/home/admin/.gemini/oauth_creds.json' /etc/homelab/backup-include.txt && grep -F '/home/admin/.gemini/antigravity-cli/cache/**' /etc/homelab/backup-excludes.txt` | Exit code 0, both manifests contain expected paths | Principle V |
| **AG-008** | Zero Credentials in Version Control | `git -C /home/admin/homelab2 status --porcelain | grep -E 'oauth_creds|google_accounts|\.env|id_ed25519'` | Exit code 1 (no credentials or private keys in git status) | Principle IV |

---

## 2. JSON Test Output Format

When invoked with `--json`, `scripts/verify-phase7-antigravity.sh` outputs:

```json
{
  "timestamp": "2026-11-02T22:00:00Z",
  "feature": "007-antigravity-remote-control",
  "target": "homelab2",
  "summary": {
    "total": 8,
    "passed": 8,
    "failed": 0,
    "duration_ms": 2850
  },
  "assertions": [
    {"id": "AG-001", "name": "Antigravity CLI Binary Available", "status": "PASS", "duration_ms": 45},
    {"id": "AG-002", "name": "User Lingering Enabled", "status": "PASS", "duration_ms": 10},
    {"id": "AG-003", "name": "Remote Control Service Active", "status": "PASS", "duration_ms": 65},
    {"id": "AG-004", "name": "Remote Control Status & Instance Registered", "status": "PASS", "duration_ms": 320},
    {"id": "AG-005", "name": "Autonomous Settings & Perms Validated", "status": "PASS", "duration_ms": 25},
    {"id": "AG-006", "name": "Host Git Workspace & Worktrees Ready", "status": "PASS", "duration_ms": 90},
    {"id": "AG-007", "name": "Backup Registration Validated", "status": "PASS", "duration_ms": 15},
    {"id": "AG-008", "name": "Zero Credentials in Version Control", "status": "PASS", "duration_ms": 40}
  ]
}
```
