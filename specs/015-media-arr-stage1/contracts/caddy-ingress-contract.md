# Contract: Media & Arr Stage 1 Caddy Ingress & Network Isolation (`ARR-INGRESS-V1`)

**Feature**: `015-media-arr-stage1`  
**Date**: 2026-11-17  
**Requirements Covered**: FR-007, SC-004, Principle IV

---

## 1. Caddy Drop-In Configuration (`/etc/caddy/conf.d/40-arr.caddy`)

```caddy
# /etc/caddy/conf.d/40-arr.caddy
# Managed by Ansible - homelab2
# Contract: ARR-INGRESS-V1
# Internal-only ingress for Media & Arr Stack (LAN + Tailscale mesh only; zero public exposure)

# Stage 1: Jellyfin Media Server
jellyfin.{$HOMELAB_DOMAIN:lan} {
    tls internal
    log {
        output stderr
        format console
        level INFO
    }

    @internal {
        remote_ip 127.0.0.0/8 192.168.4.0/24 100.64.0.0/10 ::1
    }

    handle @internal {
        reverse_proxy 127.0.0.1:{{ arr_jellyfin_port | default(8096) }} {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
        }
    }

    handle {
        respond "Forbidden: Internal network access only" 403
    }
}

# Stage 1: qBittorrent Download Client (routed via arr_vpn namespace loopback binding)
qbittorrent.{$HOMELAB_DOMAIN:lan} {
    tls internal
    log {
        output stderr
        format console
        level INFO
    }

    @internal {
        remote_ip 127.0.0.0/8 192.168.4.0/24 100.64.0.0/10 ::1
    }

    handle @internal {
        reverse_proxy 127.0.0.1:{{ arr_qbittorrent_webui_port | default(8080) }} {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
        }
    }

    handle {
        respond "Forbidden: Internal network access only" 403
    }
}

# Reserved for Stage 2A (ersatztv), Stage 2B (jellyseerr), and Stage 2C (prowlarr, radarr, sonarr)
```

---

## 2. Network Isolation & Security Invariants

1. **Strict Loopback Port Publishing**:
   - `arr_jellyfin` publishes `127.0.0.1:8096:8096`.
   - `arr_vpn` publishes `127.0.0.1:8080:8080` (for `arr_qbittorrent`; plus `127.0.0.1:8000:8000` if `arr_vpn_mode: "gluetun"`).
   - Zero Stage 1 container ports are bound to `0.0.0.0` or `[::]`.
2. **Internal-Only Reverse Proxy Access & Coexistence with Vaultwarden Funnel**:
   - Caddy (`default_bind 127.0.0.1 192.168.4.57` in `/etc/caddy/Caddyfile`) serves `jellyfin.lan` and `qbittorrent.lan` using `tls internal` and restricts access via `@internal` (`127.0.0.0/8`, `192.168.4.0/24` LAN, and `100.64.0.0/10` Tailscale CGNAT mesh).
   - Remote Tailscale devices reach `192.168.4.57:443` via Tailscale subnet routing (`--advertise-routes=192.168.4.0/24` on `fidelacchius`) while `100.103.39.60:443` remains dedicated to Vaultwarden Tailscale Funnel.
   - Any non-internal client receives HTTP `403 Forbidden`.
   - Neither service is ever exposed via Tailscale Funnel or public port-forwarding (`SC-004`).
