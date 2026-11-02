# Quickstart & Verification Guide: Network & Remote Access Overlay (Phase 3)

**Feature**: `003-network-remote-access`  
**Date**: 2026-11-01  
**Target Host**: `admin@192.168.4.57` (homelab2)  

---

## 1. Prerequisites

Before running the Phase 3 convergence:

1. **Target Host Online**: The target host `192.168.4.57` must be reachable via SSH with administrative public key authentication established in Phase 2.
2. **Master Age Key Present**: The operator workstation must have the age private key available in environment (`$env:SOPS_AGE_KEY` or `~/.config/sops/age/keys.txt`).
3. **Secrets Populated**: Tailscale auth key must be set in `ansible/inventory/group_vars/all/vault.sops.yml` (as detailed in [secrets-schema.md](file:///C:/Users/micro/projects/homelab2/specs/003-network-remote-access/contracts/secrets-schema.md)).

---

## 2. Convergence Execution

### Option A: From Windows Workstation (Recommended)

Run the automated orchestrator script which syncs configurations and executes the Phase 3 playbook:

```powershell
./scripts/apply-phase3.ps1 -TargetHost "192.168.4.57" -User "admin"
```

### Option B: Direct Ansible Invocation (from Linux/WSL or Target)

```bash
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/network.yml
```

To run the unified site convergence across all phases:

```bash
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

---

## 3. End-to-End Validation Scenarios

### Scenario 1: Automated Acceptance Test Suite

Execute the acceptance test runner against the target host:

```bash
# On target host or via SSH:
ssh admin@192.168.4.57 "bash /opt/homelab/scripts/verify-phase3.sh"
```

**Expected Outcome**:
All 8 verification checks ([NET-01 through NET-08](file:///C:/Users/micro/projects/homelab2/specs/003-network-remote-access/contracts/verification-suite.md)) return `PASS` and the script exits with code `0`.

---

### Scenario 2: Remote Mesh Connectivity Test

From an external client device (such as a laptop connected to mobile hotspot):

1. Confirm Tailscale is active on client.
2. Ping the host's Tailscale mesh IP or MagicDNS hostname:
   ```bash
   ping homelab2
   ```
3. Establish remote administrative SSH:
   ```bash
   ssh admin@homelab2
   ```

**Expected Outcome**:
Connection succeeds without router port-forwarding or public IP exposure.

---

### Scenario 3: Firewall Boundary Verification

From the local management workstation:

```bash
# Verify allowed ports accept connections:
curl -I http://192.168.4.57/health

# Verify unwhitelisted ports are dropped/filtered:
nc -zv -w 2 192.168.4.57 8080
```

**Expected Outcome**:
- `http://192.168.4.57/health` returns `HTTP/1.1 200 OK`.
- Port `8080` times out with zero response (filtered by `nftables` default drop policy).

---

### Scenario 4: HTTP to HTTPS Redirection

```bash
curl -I http://192.168.4.57/
```

**Expected Outcome**:
Returns `HTTP/1.1 308 Permanent Redirect` with `Location: https://192.168.4.57/`.

---

### Scenario 5: Reboot Convergence Assertion

```bash
ssh admin@192.168.4.57 "sudo reboot"
```

Wait 45 seconds for the host to complete reboot, then re-run:

```powershell
./scripts/verify-phase3.ps1 -TargetHost "192.168.4.57"
```

**Expected Outcome**:
Host rejoins Tailscale, nftables rules are restored, Caddy restarts, and all health assertions pass cleanly.
