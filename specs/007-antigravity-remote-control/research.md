# Research & Architecture Decisions: Target Host Antigravity Installation & Remote Control

**Feature**: `007-antigravity-remote-control`  
**Status**: Completed  
**Author**: Antigravity Assistant  

---

## 1. Antigravity CLI Installation & Environment Integration on Arch Linux

### Decision
Install the upstream Antigravity CLI (`agy`) binary into `/home/admin/.local/bin/agy` using the official curl installation stream (`curl -fsSL https://antigravity.google/cli/install.sh | bash`), and create a system-wide symlink from `/usr/local/bin/agy` to ensure it is immediately available across all interactive, non-interactive, and automated shell sessions.

### Rationale
- Arch Linux does not have `agy` in the core/extra repositories. The official upstream installer is the canonical distribution channel.
- Installing under the unprivileged `admin` operator account adheres to the principle of least privilege, while the `/usr/local/bin/agy` symlink guarantees path resolution for non-login and systemd service contexts without relying on shell dotfile loading.
- Idempotency is maintained by checking `agy --version` prior to running the installer. Re-running automation when `agy` is present performs a non-destructive version check rather than a re-download.

### Alternatives Considered
- **AUR Package (e.g., `yay -S antigravity-bin`)**: Introducing AUR helpers into headless unattended server automation adds package manager complexity, build dependencies, and third-party packaging lag.
- **Copying Windows binary / Cross-compiling**: The controller runs Windows x86_64, whereas the target server is bare-metal Arch Linux x86_64 ELF. Binary transfer from the controller would fail. The native Linux binary from upstream is required.

---

## 2. Remote Control Background Daemon & Systemd User Supervision

### Decision
Manage the Remote Control daemon using native `systemd` user management initiated by `agy remote-control start --name homelab2-target`. Ensure persistent background execution across logouts and server reboots by enabling user lingering via `loginctl enable-linger admin`.

### Rationale
- `agy remote-control start` is the native Antigravity CLI command that provisions `~/.config/systemd/user/agy-remote-control.service`.
- On Linux, systemd terminates user service managers (`systemd --user`) when the user's last interactive login session disconnects. Enabling linger (`loginctl enable-linger admin`) causes systemd to spawn the user manager at system boot and keep it alive indefinitely, satisfying FR-002 and SC-001.
- Service supervision, automated restart on failure (`Restart=always`), and journal logging (`journalctl --user -u agy-remote-control.service`) are provided out of the box by systemd, satisfying FR-003 and FR-009.

### Alternatives Considered
- **System-level systemd unit (`/etc/systemd/system/antigravity.service`)**: The `agy` CLI natively configures and registers user-level systemd units. Hand-crafting a system-level unit risks drift when upstream CLI updates change runtime parameters or internal flags.
- **Tmux / Screen session**: Lacks boot persistence, automated health restart, structured journald logging, and crashes on reboot without interactive intervention.

---

## 3. Autonomous Execution & Tool Permission Policy

### Decision
Configure `/home/admin/.gemini/antigravity-cli/settings.json` with `"toolPermission": "always-proceed"` and `"agentMode": "auto"`, granting pre-approved permissions for file editing and command execution in the target workspace `/home/admin/homelab2`.

### Rationale
- When interacting with the target host via Remote Control from mobile devices or external web browsers, interactive confirmation prompts for terminal commands and file edits block autonomous execution, causing multi-step build-out tasks to hang.
- Setting `"toolPermission": "always-proceed"` (the persistent configuration equivalent of `--dangerously-skip-permissions`) fulfills FR-005 and the user clarification session.
- System safeguards (Principle II) and offsite encrypted Backblaze B2 backups (Principle V) provide the safety net for state recovery.

### Alternatives Considered
- **`request-review` (default)**: Hangs waiting for local terminal or mobile UI approval for every action, making unattended automation impossible.
- **`proceed-in-sandbox`**: Restricts tool execution and blocks root/sudo commands and certain filesystem operations needed to manage homelab infrastructure.

---

## 4. Authentication Profile Seeding & Interactive Fallback Flow

### Decision
Implement a 3-tier authentication resolution strategy:
1. **Encrypted Disaster Recovery Restore**: If restoring from Backblaze B2, Restic extracts `/home/admin/.gemini/oauth_creds.json` and `google_accounts.json`.
2. **Controller Profile Seeding**: During initial Ansible provisioning, if a local seed exists in gitignored `secrets/antigravity/oauth_creds.json` or the controller's `~/.gemini/oauth_creds.json`, Ansible securely pushes it to `/home/admin/.gemini/oauth_creds.json` (`0600 admin:admin`).
3. **One-Time OAuth URL Fallback**: If no credentials exist, the setup script surfaces the one-time Google OAuth authorization URL generated by `agy` to the operator's console and pauses for completion before registering the daemon.

### Rationale
- Satisfies FR-006 and the explicit user clarification: automated seeding avoids redundant authentication flows, while the one-time URL fallback ensures seamless bootstrap on a fresh machine.
- File permissions are locked to `0600 admin:admin`, ensuring no unprivileged local accounts can read OAuth tokens.

### Alternatives Considered
- **Storing API keys in Ansible inventory**: Prohibited by Principle IV (Zero Secrets in Version Control).
- **Hardcoding tokens in environment files**: Fragile, violates credential isolation, and risks token leakage.

---

## 5. Host Project Workspace Readiness & Dedicated Git Authentication

### Decision
Provision `/home/admin/homelab2` as a dedicated git clone of the upstream repository, authenticated via a dedicated SSH deploy key (`/home/admin/.ssh/id_ed25519_github` with permissions `0600 admin:admin`). Configure Git identity and SSH config to route `github.com` requests through this key.

### Rationale
- Fulfills FR-004 and User Story 2. The remote agent needs full read/write capabilities on git branches and worktrees to push/pull changes while the operator is away.
- A dedicated SSH key decouples host git access from personal workstation keys and can be revoked or rotated independently.
- The private key is excluded from git and registered in the encrypted offsite Restic backup.

### Alternatives Considered
- **HTTPS Git Token in `~/.git-credentials`**: Plaintext tokens are prone to accidental exposure; SSH public key authentication provides stronger cryptographic isolation.
- **Sharing primary workstation SSH key**: Violates principle of least privilege and machine credential separation.

---

## 6. Encrypted Offsite Backup Integration (Backblaze B2 / Restic)

### Decision
Integrate Antigravity and Git credentials into the existing Phase 6 Restic backup architecture:
1. Append to `/etc/homelab/backup-include.txt`:
   - `/home/admin/.gemini/oauth_creds.json`
   - `/home/admin/.gemini/google_accounts.json`
   - `/home/admin/.gemini/antigravity-cli/settings.json`
   - `/home/admin/.ssh/id_ed25519_github`
   - `/home/admin/.ssh/id_ed25519_github.pub`
2. Append to `/etc/homelab/backup-excludes.txt`:
   - `/home/admin/.gemini/antigravity-cli/cache/**`
   - `/home/admin/.gemini/antigravity-cli/crashes/**`
   - `/home/admin/.gemini/antigravity-cli/log/**`
   - `/home/admin/.gemini/antigravity-cli/updater/**`
   - `/home/admin/.gemini/antigravity-cli/brain/**`
   - `/home/admin/.gemini/tmp/**`
   - `/home/admin/homelab2/.git/**`

### Rationale
- Fulfills Principle V, FR-007, and FR-008. Essential credentials and settings are captured in offsite encrypted snapshots, allowing full recovery without re-authorizing Google accounts or re-generating deploy keys.
- Ephemeral caches, crash reports, conversation transcripts, and git internal object trees are excluded to prevent backup bloat and preserve network bandwidth.

### Alternatives Considered
- **Backing up the entire `/home/admin` directory**: Backs up hundreds of megabytes of transient caches, compiler artifacts, and duplicated Git object databases.
- **Excluding `.gemini` completely**: Forces the operator to manually re-authenticate via OAuth on every disaster recovery event.

---

## 7. Safety Gate Enforcement (FR-011)

### Decision
Implement an explicit live-target confirmation guard in `scripts/apply-phase7-antigravity.ps1` and `scripts/apply-phase7-antigravity.sh`. Unless `--confirm-target-ready` is explicitly provided, the script pauses with an interactive prompt or halts with an error explaining that live execution against `admin@192.168.4.57` is prohibited until confirmed.

### Rationale
- Fulfills FR-011: "Automation workflows and agents MUST NOT execute live provisioning or verification against `admin@192.168.4.57` until the operator explicitly confirms the target machine is ready."
- Protects the live environment from unintended runs while development and testing occur in the worktree.
