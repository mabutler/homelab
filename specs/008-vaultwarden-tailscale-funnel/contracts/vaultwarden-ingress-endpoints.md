# Interface Contract: Vaultwarden Ingress & Public Endpoints

**Feature Branch**: `008-vaultwarden-tailscale-funnel`  
**Date**: 2026-11-03  

## 1. External Public Ingress Endpoints

Exposed publicly over HTTPS on `https://<node-name>.<tailnet>.ts.net:443`.

### 1.1 Health Probe (`/alive`)
- **Protocol**: HTTPS (GET)
- **Host Header**: `<node-name>.<tailnet>.ts.net`
- **Expected Status**: `200 OK`
- **Content**: Empty or text status
- **Contract Assertion**: Proves Let's Encrypt TLS handshake succeeded, Tailscale edge proxy routed request to node, and Vaultwarden backend responded.

### 1.2 Configuration API (`/api/config`)
- **Protocol**: HTTPS (GET)
- **Expected Status**: `200 OK`
- **Response Format**: `application/json`
- **Critical Assertions**:
  ```json
  {
    "signupsAllowed": false,
    "websocketEnabled": true,
    "domain": "https://<node-name>.<tailnet>.ts.net"
  }
  ```
- **Contract Assertion**: Confirms signups are disabled to the public, real-time sync is enabled, and domain matches the public FQDN.

### 1.3 WebSocket Notification Hub (`/notifications/hub`)
- **Protocol**: WSS (WebSocket over HTTPS)
- **Upgrade Headers Required**:
  - `Connection: Upgrade`
  - `Upgrade: websocket`
  - `Sec-WebSocket-Version: 13`
  - `Sec-WebSocket-Key: <base64-nonce>`
- **Expected Status**: `101 Switching Protocols` (or `401 Unauthorized` / protocol upgrade message if unauthenticated)
- **Contract Assertion**: Validates that bidirectional streaming is not blocked by Tailscale edge proxies or firewalls.

---

## 2. Internal Service Ingress Endpoints (Caddy)

- **HTTP Port 80 Health**: `http://127.0.0.1:80/health` -> `200 OK`
- **HTTP Port 80 Fallback**: `http://127.0.0.1:80/` -> `301/308 Redirect` to `https://`
- **Vaultwarden via Caddy**: Decommissioned (no longer exposed on `vaultwarden.lan` or through Caddy reverse proxy).
