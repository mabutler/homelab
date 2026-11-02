# Contract: Automated Verification Suite (Phase 3)

**Feature**: `003-network-remote-access`  
**Contract ID**: `CNTR-NET-004`  
**Status**: Ratified  

---

## 1. Scope & Quality Gate Compliance

In accordance with Constitution Principle III (Automated Verification & Acceptance Gates), Phase 3 is the pivotal phase establishing full network connectivity. Therefore, **telemetry, observability, and service health checks are mandatory completion gates**.

The verification suite runs via:
- Shell verification script: `scripts/verify-phase3.sh`
- Ansible verification playbook: `ansible/playbooks/verify-phase3.yml` (and unified `ansible/playbooks/verify.yml`)

---

## 2. Assertion Matrix

| Test ID | Subsystem | Check Command / Assertion | Expected Result | Exit Code on Failure |
|---|---|---|---|---|
| **NET-01** | nftables | `systemctl is-active nftables.service` | `active` | 1 |
| **NET-02** | nftables | `nft list table inet filter` | Ruleset contains input drop policy & whitelisted ports | 2 |
| **NET-03** | Tailscale | `systemctl is-active tailscaled.service` | `active` | 3 |
| **NET-04** | Tailscale | `tailscale status --json` | `.BackendState == "Running"` or node is authenticated | 4 |
| **NET-05** | Caddy | `systemctl is-active caddy.service` | `active` | 5 |
| **NET-06** | Ingress | `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:80/health` | `200` | 6 |
| **NET-07** | Ingress | `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:80/` | `301` or `308` (HTTPS redirect) | 7 |
| **NET-08** | Ingress | `ss -tulpn` | Listening on ports 80, 443, 22, and 41641/udp | 8 |

---

## 3. Exit Code Contract

- `0`: All assertions passed. Network and remote access overlay is fully functional.
- `1-8`: Specific assertion failure as enumerated above. Detailed diagnostic emitted to `stderr`.
