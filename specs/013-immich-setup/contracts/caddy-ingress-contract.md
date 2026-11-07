# Contract: Immich Caddy Ingress & Network Security (`IMMICH-INGRESS-V1`)

**Feature**: `013-immich-setup`  
**Date**: 2026-11-06  
**Requirements Covered**: FR-006, SC-003, Principle IV

---

## 1. Caddy Drop-In Configuration (`/etc/caddy/conf.d/30-immich.caddy`)

```caddy
# /etc/caddy/conf.d/30-immich.caddy
# Managed by Ansible - homelab2
# Contract: IMMICH-INGRESS-V1

# Immich Photo Management Platform
photos.{$HOMELAB_DOMAIN:lan}, https://photos.fidelacchius.ts.net {
    log {
        output stderr
        format console
        level INFO
    }

    # Support multi-gigabyte photo and video uploads (up to 50 GB per upload batch)
    request_body {
        max_size 50GB
    }

    # Reverse proxy to Immich loopback server binding
    reverse_proxy 127.0.0.1:2283 {
        # Streaming and connection timeouts
        transport http {
            dial_timeout 30s
            response_header_timeout 300s
        }

        # WebSocket support handled natively by Caddy reverse_proxy
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
```

---

## 2. Ingress Security & Network Isolation Rules

1. **Loopback Only**: `immich-server` publishes port `2283` exclusively on `127.0.0.1`. Direct external access to `0.0.0.0:2283` is blocked by the host `nftables` firewall.
2. **TLS Termination**: All client connections over LAN (`192.168.4.0/24`) and Tailscale (`tailscale0`) terminate TLS at Caddy.
3. **Payload Buffering**: Ingress allows payload streaming up to `50GB` per request body, preventing HTTP 413 errors on bulk mobile photo library ingest or 4K video uploads.
4. **WebSocket Compatibility**: Reverse proxy preserves persistent bidirectional WebSocket connections for real-time mobile background sync and job progression events.
