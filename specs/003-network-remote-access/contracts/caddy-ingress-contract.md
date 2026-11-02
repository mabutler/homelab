# Contract: Caddy Ingress & Reverse Proxy Schema

**Feature**: `003-network-remote-access`  
**Contract ID**: `CNTR-NET-001`  
**Status**: Ratified  

---

## 1. Directory Structure & Layout

The Caddy configuration adheres to a modular drop-in structure on the host:

```text
/etc/caddy/
├── Caddyfile                  # Main entry point with global options and imports
└── conf.d/                    # Modular drop-in directory for application routes
    ├── 00-health.caddy        # Core health assertion endpoint
    └── *.caddy                # Future per-service route definitions (Phase 5)
```

---

## 2. Main Entry Point (`/etc/caddy/Caddyfile`)

```caddy
# Global configuration block
{
    # Log configuration: structured JSON output to stdout/journald
    log {
        output stderr
        format console
        level INFO
    }

    # Disable admin API port or bind to local unix socket
    admin off
}

# Import all service drop-in configurations
import /etc/caddy/conf.d/*.caddy
```

---

## 3. Core Health & Default Drop-in (`/etc/caddy/conf.d/00-health.caddy`)

```caddy
# Local health check endpoint (plain HTTP on localhost or internal IP)
:80 {
    handle /health {
        respond "OK" 200
    }

    # Default fallback redirect to HTTPS for general traffic
    handle {
        redir https://{host}{uri} permanent
    }
}
```

---

## 4. Upstream Service Ingress Specification (Template for Applications)

When applications are deployed in Phase 5, they supply a drop-in file following this standard contract:

```caddy
# Example service drop-in: /etc/caddy/conf.d/10-service.caddy
subdomain.example.com {
    # TLS generation: automated ACME or Tailscale TLS
    tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    }

    # Reverse proxy with automatic WebSocket support and transparent header forwarding
    reverse_proxy 127.0.0.1:8080 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
```

---

## 5. Error Handling Contract

- **Backend Offline (502)**: If an upstream backend service is unreachable, Caddy returns an HTTP 502 Bad Gateway response within 3 seconds without crashing or stalling other virtual hosts.
- **Syntax Check**: Prior to reloading `caddy.service`, configuration changes MUST be validated with `caddy validate --config /etc/caddy/Caddyfile`. If the check fails, the existing daemon remains untouched.
