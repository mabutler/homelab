# Quickstart & Operational Validation Guide: Target Host Antigravity & Remote Control

**Feature**: `007-antigravity-remote-control`  
**Target Host**: `admin@192.168.4.57` (`homelab2`)  

---

## 1. Prerequisites

1. **Host Readiness**:
   - The target host `admin@192.168.4.57` must have completed Phases 1-4 (base system, hardening, networking, storage).
   - Operator confirmation must be given before live execution (FR-011).
2. **Google Antigravity Account**:
   - An authorized Google account with Antigravity access.
   - If available, seed credentials placed in `secrets/antigravity/oauth_creds.json` on the controller workstation, or be prepared to complete the one-time browser OAuth flow during initial setup.
3. **GitHub SSH Deploy Key**:
   - An SSH key authorized on GitHub for `homelab2` push/pull operations (e.g. `secrets/ssh/id_ed25519_github`).

---

## 2. Deployment & Convergence

### Step 1: Execute Deployment Script
Run the automated deployment script from your workstation (note the mandatory `--confirm-target-ready` guard):

```powershell
# From repo root on workstation:
./scripts/apply-phase7-antigravity.ps1 -HostAddress 192.168.4.57 -User admin -ConfirmTargetReady
```

Or execute directly on the target host:
```bash
./scripts/apply-phase7-antigravity.sh --confirm-target-ready
```

### Step 2: Handle First-Time OAuth (if not seeded)
If credentials were not pre-seeded:
1. The script displays a one-time Google Sign-In URL.
2. Open the URL on your phone or workstation browser, approve access, and copy the verification code back into the prompt if required.
3. The script verifies successful token acquisition and starts the background daemon.

---

## 3. End-to-End Validation Scenarios

### Scenario 1: Automated Verification Suite (AG-001 through AG-008)
Execute the automated acceptance verification suite:

```powershell
# From workstation:
./scripts/verify-phase7-antigravity.ps1 -TargetHost 192.168.4.57 -User admin
```

Or on the target host:
```bash
./scripts/verify-phase7-antigravity.sh
```

**Expected Outcome**:
All 8 assertions pass (`[PASS] AG-001` through `[PASS] AG-008`) with exit code 0. See [`verification-suite-contract.md`](contracts/verification-suite-contract.md).

---

### Scenario 2: Remote Instruction via Antigravity Web / Mobile Interface
Validate that the daemon is reachable and can execute tasks autonomously:

1. Open `https://antigravity.google` on your mobile device or remote laptop.
2. Verify that **`homelab2-target`** appears in the machine list with an **Online** status indicator.
3. Connect to `homelab2-target` and select workspace `/home/admin/homelab2`.
4. Send an instruction:
   ```text
   Verify system storage status using df -h and check mergerfs mount health.
   ```
5. Confirm that the agent executes the terminal commands autonomously without blocking on permission approval prompts, and streams results back to the remote screen.

---

### Scenario 3: Reboot Persistence (Boot without Interactive Login)
Validate that user lingering and systemd user services restart cleanly across reboots:

1. Reboot the target host:
   ```bash
   sudo reboot
   ```
2. Wait 60 seconds after the machine reboots without initiating an interactive SSH session.
3. Refresh the Remote Control dashboard on your mobile device.
4. Confirm `homelab2-target` automatically reconnects and returns to **Online** state.
5. SSH in to verify the systemd user service state:
   ```bash
   ssh admin@192.168.4.57 "systemctl --user is-active agy-remote-control.service"
   # Output: active
   ```

---

### Scenario 4: Worktree Creation & Git Push/Pull Verification
Validate that the agent on the target machine can create an isolated worktree and interact with GitHub:

1. Via Remote Control, send the instruction:
   ```text
   Create a new git worktree for a test feature under .worktrees/remote-test-feature, verify git status, and push a tracking branch to origin.
   ```
2. Verify that the agent creates `/home/admin/homelab2/.worktrees/remote-test-feature` cleanly, executes `git push`, and cleans up the test worktree without error.

---

### Scenario 5: Disaster Recovery Restore Rehearsal
Verify that restored credentials from Backblaze B2 recover the Antigravity agent profile without manual OAuth:

```bash
# SSH into homelab2
ssh admin@192.168.4.57

# Recover .gemini and .ssh to a temporary test directory
sudo /usr/local/bin/homelab-backup restore --target /tmp/dr-test --include "/home/admin/.gemini/oauth_creds.json"

# Validate recovered file
test -f /tmp/dr-test/home/admin/.gemini/oauth_creds.json && echo "Restore verified"
```
