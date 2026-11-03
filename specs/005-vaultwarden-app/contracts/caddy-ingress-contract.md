# Contract: Caddy Reverse Proxy Ingress Drop-In

**Feature**: `005-vaultwarden-app` | **Date**: 2026-11-01

This contract defines the ingress routing specification, header manipulation, TLS policy, and WebSocket handling for Vaultwarden integrated with Caddy.

---

## 1. File Path & Location

The ingress drop-in MUST be deployed to:
`/etc/caddy/conf.d/20-vaultwarden.caddy`

---

## 2. Ingress Configuration Contract

```caddy
# Managed by Ansible - do not edit manually
# Ingress routing for Vaultwarden password manager

vaultwarden.lan, vaultwarden.{$HOMELAB_DOMAIN:local} {
    tls internal

    # Security headers
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains;"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        X-XSS-Protection "1; mode=block"
        Referrer-Policy "same-origin"
        -Server
    }

    # Proxy all traffic (including WebSocket upgrades on /notifications/hub) to backend
    reverse_proxy 127.0.0.1:8088 {
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
```

---

## 3. Behavioral Contracts & Verification

| Property | Requirement | Expected Behavior |
|---|---|---|
| **HTTPS Redirection** | HTTP requests to `http://vaultwarden.lan` | Automatically redirected to `https://vaultwarden.lan` (308/301). |
| **TLS Certificate** | Automatic internal TLS | Handshake succeeds using Caddy's local root CA or configured ACME. |
| **Health Check** | `GET /alive` | Returns HTTP 200 OK within 500ms. |
| **WebSocket Upgrade** | `GET /notifications/hub` with `Upgrade: websocket` | Returns HTTP 101 Switching Protocols and maintains bidirectional connection. |
| **Web Vault UI** | `GET /` | Returns HTTP 200 with Bitwarden web vault HTML/JS assets. |
| **Admin Portal** | `GET /admin` | Protected by admin token authentication. |
