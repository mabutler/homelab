# Contract: Target Host Workspace & Autonomous Permissions

**Contract Identifier**: `AG-WORKSPACE-V1`  
**Target Host**: `admin@192.168.4.57` (`homelab2`)  
**Workspace Root**: `/home/admin/homelab2`  

---

## 1. CLI Settings & Autonomous Permission Policy

### 1.1 Configuration File Specification
Persistent CLI configuration MUST be maintained in `/home/admin/.gemini/antigravity-cli/settings.json` with permissions `0600 admin:admin`:

```json
{
  "toolPermission": "always-proceed",
  "agentMode": "auto",
  "model": "Gemini 3.8 Flash (Medium)",
  "trustedWorkspaces": [
    "/home/admin/homelab2"
  ]
}
```

### 1.2 Policy Rules
- **Autonomous Tool Execution**: `"toolPermission": "always-proceed"` auto-approves all tool permission requests (terminal execution, file modifications, git operations) without prompting the operator.
- **Trusted Workspace**: `/home/admin/homelab2` is explicitly registered in `trustedWorkspaces` to allow unprompted edits and git commands within the project repository and its worktrees.

---

## 2. Host Project Git Repository Checkout

### 2.1 Workspace Structure
The repository is cloned to `/home/admin/homelab2`:
- **Owner**: `admin:admin`
- **Worktrees Subdirectory**: `/home/admin/homelab2/.worktrees/`
- **Git Config**:
  - `user.name`: Configured operator identity
  - `user.email`: Configured operator email

### 2.2 Dedicated Git Authentication (SSH Deploy Key)
To allow the remote agent to push and pull branches to/from GitHub without prompting for passwords:
- **Private Key**: `/home/admin/.ssh/id_ed25519_github` (mode `0600 admin:admin`)
- **Public Key**: `/home/admin/.ssh/id_ed25519_github.pub` (mode `0644 admin:admin`)
- **SSH Configuration**: `/home/admin/.ssh/config` containing:
  ```sshconfig
  Host github.com
      HostName github.com
      User git
      IdentityFile ~/.ssh/id_ed25519_github
      IdentitiesOnly yes
      StrictHostKeyChecking accept-new
  ```
- **Validation**: `ssh -T git@github.com` must connect successfully.

---

## 3. Worktree Isolation Workflow

When the remote agent executes tasks via Remote Control:
1. Feature worktrees MUST be created in `/home/admin/homelab2/.worktrees/<feature-name>`.
2. Worktree creation command:
   ```bash
   git -C /home/admin/homelab2 worktree add .worktrees/<branch-name> -b <branch-name>
   ```
3. Worktrees run automation against the local host using the local repository playbooks and scripts.
