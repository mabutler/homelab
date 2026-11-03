# Operational Runbook: Target Host Antigravity & Remote Control

This runbook documents day-to-day operations, lifecycle management, troubleshooting, and disaster recovery procedures for the Google Antigravity Remote Control daemon on `homelab2` (`admin@192.168.4.57`).

---

## 1. Overview & Architecture

The Google Antigravity CLI (`agy`) runs as a persistent background daemon (`agy-remote-control.service`) under systemd user supervision on the target server. It connects outward via WSS/HTTPS to Google Antigravity servers, allowing the operator to manage, inspect, and build out homelab features remotely from mobile devices or web browsers without requiring inbound firewall ports.

- **Operator User**: `admin`
- **Binary Path**: `/home/admin/.local/bin/agy` (symlinked from `/usr/local/bin/agy`)
- **Systemd Unit**: `/home/admin/.config/systemd/user/agy-remote-control.service`
- **Instance Name**: `homelab2-target`
- **Configuration**: `/home/admin/.gemini/antigravity-cli/settings.json` (mode `0600 admin:admin`)
- **Workspace**: `/home/admin/homelab2` (with `.worktrees/` directory for isolated feature development)
- **Git Key**: `/home/admin/.ssh/id_ed25519_github` (dedicated deploy key)

---

## 2. Common Operational Commands

### 2.1 Service Management

The daemon is supervised by the `admin` user's systemd instance. To inspect or control the service:

```bash
# Check service status via CLI
agy remote-control status

# Check systemd user service state
systemctl --user status agy-remote-control.service

# Restart the daemon
systemctl --user restart agy-remote-control.service

# View live streaming daemon logs
journalctl --user -u agy-remote-control.service -f --no-pager

# View recent 50 lines of logs
journalctl --user -u agy-remote-control.service -n 50 --no-pager
```

### 2.2 Boot Persistence & Lingering

User lingering is enabled via `loginctl enable-linger admin`. This ensures `systemd --user` launches at boot without requiring an active SSH session.
To verify:
```bash
test -f /var/lib/systemd/linger/admin && echo "Lingering enabled"
```

---

## 3. Remote Development Workflow (Isolated Worktrees)

When executing tasks via Remote Control:
1. Always create feature worktrees under `/home/admin/homelab2/.worktrees/`:
   ```bash
   git -C /home/admin/homelab2 worktree add .worktrees/<feature-name> -b <feature-name>
   ```
2. Develop, test, and run playbooks locally inside the worktree directory.
3. Push changes to GitHub using the dedicated deploy key:
   ```bash
   git push -u origin <feature-name>
   ```
4. Remove the worktree upon PR merge:
   ```bash
   git -C /home/admin/homelab2 worktree remove .worktrees/<feature-name>
   ```

---

## 4. Deployment & Verification Orchestration

### 4.1 Deployment (Enforces FR-011 Safety Guard)

From workstation (PowerShell):
```powershell
./scripts/apply-phase7-antigravity.ps1 -HostAddress 192.168.4.57 -User admin -ConfirmTargetReady
```

From server (Bash):
```bash
./scripts/apply-phase7-antigravity.sh --confirm-target-ready
```

### 4.2 Automated Acceptance Verification (AG-001 through AG-008)

From workstation:
```powershell
./scripts/verify-phase7-antigravity.ps1 -TargetHost 192.168.4.57 -User admin
```

From server:
```bash
./scripts/verify-phase7-antigravity.sh
# or structured JSON:
./scripts/verify-phase7-antigravity.sh --json
```

---

## 5. Backup & Disaster Recovery

### 5.1 Centralized Backup Coverage
Authentication profiles and settings are automatically included in daily Backblaze B2 snapshots:
- `/home/admin/.gemini/oauth_creds.json`
- `/home/admin/.gemini/google_accounts.json`
- `/home/admin/.gemini/antigravity-cli/settings.json`
- `/home/admin/.ssh/id_ed25519_github`
- `/home/admin/.ssh/id_ed25519_github.pub`

Ephemeral caches, model files, crash telemetry, and Git databases are excluded to avoid backup bloat.

### 5.2 Recovery Procedure
1. Run `scripts/restore-from-b2.sh` to extract the latest snapshot.
2. Re-apply the deployment playbook:
   ```bash
   ./scripts/apply-phase7-antigravity.sh --confirm-target-ready
   ```
3. The daemon starts immediately with existing credentials without requiring interactive browser OAuth.
