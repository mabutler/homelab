# Disaster Recovery Procedure: Network & Remote Access Overlay (Phase 3)

**Feature**: `003-network-remote-access`  
**Constitution Principle**: Principle V (Disaster Recovery & Backup by Design)  
**Target Recovery Time Objective (RTO)**: < 5 minutes  
**Target Recovery Point Objective (RPO)**: 0 (Git-tracked declarative configuration)

---

## 1. Overview & Disaster Scenarios

In the event of total operating system drive failure, corrupted network filtering rules, or catastrophic host compromise, this procedure restores the network overlay (`tailscale`), host packet filter (`nftables`), and ingress reverse proxy (`caddy`) on clean hardware or a newly reinstalled Arch Linux host.

Because all configurations are declarative and tracked in Git, and all secrets (Tailscale auth key, administrative credentials) are encrypted at rest with SOPS and age, no manual reconfiguration of upstream routers, firewall port forwards, or static IP bindings is required.

---

## 2. Prerequisites for Recovery

1. **Bare-Metal Base OS Online**:
   - Clean Arch Linux installation running with administrative user `admin` and passwordless sudo access (established via Phase 1 installer and Phase 2 hardening).
   - Reachable via local management network at `192.168.4.57` with SSH public key authentication.
2. **Operator Workstation with Master Age Key**:
   - The operator's master age private key (`age10ct0eazlhgfjy7ezt7sffprjzs0tjhzpr0wngkmjdf9x5d4z9s5qx6jn6c`) available at:
     - Linux/macOS: `~/.config/sops/age/keys.txt`
     - Windows: `$env:USERPROFILE\.config\sops\age\keys.txt` or `$env:SOPS_AGE_KEY_FILE`
     - Physical paper/QR code backup (refer to [docs/recovery/age-key-backup.md](file:///C:/Users/micro/projects/homelab2/docs/recovery/age-key-backup.md))

---

## 3. Reconstitution Execution Steps (Under 5 Minutes)

### Step 1: Clone Repository & Confirm Secrets Decryption

On the operator workstation:

```bash
git clone https://github.com/<owner>/homelab2.git
cd homelab2
```

Verify that the age master private key can decrypt vault secrets:

```bash
# Optional preflight test (if sops CLI installed locally)
sops -d ansible/inventory/group_vars/all/vault.sops.yml
```

### Step 2: Trigger Automated Convergence Orchestrator

Execute the Phase 3 convergence runner to push roles, decrypt secrets in memory on the target, and converge services:

**From Windows Workstation**:

```powershell
./scripts/apply-phase3.ps1 -HostAddress "192.168.4.57" -User "admin"
```

**From Linux/macOS Workstation**:

```bash
./scripts/apply-phase3.sh --host "192.168.4.57" --user "admin"
```

The orchestrator will:
1. Validate SSH connectivity and dependencies (`ansible-core`, `sops`, `age`, `python-yaml`) on the target.
2. Securely synchronize the Ansible collection dependencies (`community.sops`).
3. Deploy and authenticate `tailscale` with `tailscale up --authkey=...` using the encrypted auth key.
4. Atomically validate and load `/etc/nftables.conf` with default-drop rules.
5. Deploy and start `caddy` reverse proxy with the `/health` drop-in endpoint.

---

## 4. Acceptance & Health Verification

Immediately after convergence, run the automated Phase 3 acceptance test suite to verify full system restoration:

**From Windows Workstation**:

```powershell
./scripts/verify-phase3.ps1 -TargetHost "192.168.4.57"
```

**From Linux/macOS Workstation or Target Host**:

```bash
./scripts/verify-phase3.sh --host "192.168.4.57"
```

**Expected Outcome**:
All 8 verification checks (NET-01 through NET-08) return `PASS` and exit code `0`:
- `nftables.service` active with input default drop policy
- `tailscaled.service` active and authenticated on mesh network
- `caddy.service` active with HTTP 200 on `/health` and 301/308 HTTPS redirect
- Listening sockets confirmed on ports 22, 80, 443, and 41641/udp

---

## 5. Tailscale Node Re-authorization (if using non-reusable keys)

If the Tailscale auth key was single-use and has expired:
1. Log in to the [Tailscale Admin Console](https://login.tailscale.com/admin).
2. Generate a new pre-authenticated auth key.
3. Update `vault_tailscale_auth_key` in `ansible/inventory/group_vars/all/vault.sops.yml` using `sops`.
4. Re-run `./scripts/apply-phase3.ps1` or `./scripts/apply-phase3.sh`.
