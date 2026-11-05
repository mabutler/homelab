# Contract: Tailscale Network Overlay & Public Funnel Ingress

**Contract ID**: `TAILSCALE-INGRESS-V1`  
**Feature**: `010-fidelacchius-system-rename`  
**Status**: Active  

---

## 1. Node Identity Interface

### 1.1 Machine Name
- **Property**: Node name on the tailnet
- **Command**: `tailscale status --json | jq -r '.Self.HostName'`
- **Expected Value**: `fidelacchius`
- **Constraint**: Must NOT contain a hyphenated suffix (e.g. `fidelacchius-1`).

### 1.2 MagicDNS Domain
- **Property**: Full DNS Name on Tailscale MagicDNS
- **Command**: `tailscale status --json | jq -r '.Self.DNSName'`
- **Expected Value**: `fidelacchius.fable-mackarel.ts.net.`

---

## 2. Public Ingress & Funnel Route

### 2.1 Funnel Status
- **Property**: Tailscale Funnel listener on HTTPS port 443
- **Command**: `tailscale funnel status --json`
- **Validation**:
  - `AllowFunnel` must contain `:443`
  - Target destination must forward to internal service port `8088` (Vaultwarden)
  - Public URL must be `https://fidelacchius.fable-mackarel.ts.net`

### 2.2 Application Ingress Contract (Vaultwarden)
- **Configuration File**: `/opt/services/vaultwarden/.env`
- **Variable**: `DOMAIN="https://fidelacchius.fable-mackarel.ts.net"`
- **HTTP Response Verification**:
  ```bash
  curl -fsSLI -k --resolve fidelacchius.fable-mackarel.ts.net:443:127.0.0.1 https://fidelacchius.fable-mackarel.ts.net
  # Expected: HTTP 200 OK or HTTP 302 Redirect, server responds without TLS or header mismatch errors
  ```
