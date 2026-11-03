# Interface Contract: Tailscale Funnel CLI & Status Schema

**Feature Branch**: `008-vaultwarden-tailscale-funnel`  
**Date**: 2026-11-03  

## 1. CLI Execution Contract

### Funnel Activation Command
```bash
tailscale funnel --bg --yes 8088
```
- **Exit Code 0**: Funnel successfully configured and backgrounded.
- **Non-zero Exit Code**: Tailscale daemon unreachable, node not authenticated, or tailnet policy forbids Funnel.

### Funnel Status Command
```bash
tailscale funnel status --json
```

### Funnel Status JSON Response Schema
```json
{
  "AllowFunnel": {
    "<fqdn>:443": true
  },
  "Web": {
    "<fqdn>:443": {
      "Handlers": {
        "/": {
          "Proxy": "http://127.0.0.1:8088"
        }
      }
    }
  }
}
```
- Inactive state: `{}` (empty JSON object).
- Active state: contains key corresponding to port 443 with `Proxy` pointing to `http://127.0.0.1:8088`.

---

## 2. Dynamic FQDN Query Schema

### Command
```bash
tailscale status --json
```

### Essential JSON Output Paths
- `Self.DNSName`: e.g. `"node.tailnet.ts.net."` (FQDN with trailing dot)
- `CertDomains`: e.g. `["node.tailnet.ts.net"]` (canonical TLS domain array)
- `BackendState`: `"Running"` when connected to tailnet
