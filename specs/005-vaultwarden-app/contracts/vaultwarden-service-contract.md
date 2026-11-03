# Contract: Vaultwarden Container & Systemd Service

**Feature**: `005-vaultwarden-app` | **Date**: 2026-11-01

This contract specifies the container execution environment, Compose manifest schema, volume bindings, environment interface, and systemd service unit contract for Vaultwarden.

---

## 1. Directory & Storage Contract

The service operates strictly within `/opt/services/vaultwarden`:

```text
/opt/services/vaultwarden/
├── compose.yml              # Declarative Docker Compose manifest (0644)
├── .env                     # Rendered environment & secrets (0600, root:root or admin:storage)
├── data/                    # Persistent application data volume (0750, 1000:1000)
│   ├── db.sqlite3           # Core SQLite database
│   ├── attachments/         # Vault encrypted file attachments
│   └── rsa_key.*            # Service crypto key pairs
├── backups/                 # Staged transactional backup archives (0750)
└── scripts/                 # Operational scripts (0755)
    ├── backup.sh            # Transactional backup execution script
    └── restore.sh           # Verified recovery script
```

---

## 2. Docker Compose Manifest Contract (`compose.yml`)

The declarative Compose specification MUST adhere to the following schema:

```yaml
version: "3.8"

services:
  vaultwarden:
    image: vaultwarden/server:1.32.7-alpine
    container_name: vaultwarden
    restart: unless-stopped
    user: "1000:1000"
    ports:
      - "127.0.0.1:8088:80"
    volumes:
      - /opt/services/vaultwarden/data:/data
    env_file:
      - .env
    environment:
      - WEBSOCKET_ENABLED=true
      - ENABLE_DB_WAL=true
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:80/alive"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
    security_opt:
      - no-new-privileges:true
```

### Constraints & Invariants
- **Port Binding**: Port 80 inside the container MUST bind exclusively to `127.0.0.1:8088` on the host. External network interfaces MUST NOT have access to port 8088 directly.
- **Process Identity**: Must run under a non-root UID/GID (`user: "1000:1000"` or matching service user).
- **Restart Policy**: `unless-stopped` to survive unexpected host restarts or container daemon reloads.
- **Image Pinning**: The image tag MUST be explicitly pinned to a stable version (e.g., `1.32.7-alpine`), never `:latest`.

---

## 3. Systemd Service Unit Contract (`vaultwarden.service`)

The application is managed on the host as a standard systemd service unit:

```ini
[Unit]
Description=Vaultwarden Password Manager (Docker Compose)
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/services/vaultwarden
ExecStart=/usr/bin/docker compose up -d --remove-orphans
ExecStop=/usr/bin/docker compose down
ExecReload=/usr/bin/docker compose up -d --remove-orphans
TimeoutStartSec=120
TimeoutStopSec=60

[Install]
WantedBy=multi-user.target
```

### Invariants
- **Service Dependency**: `Requires=docker.service` and `After=docker.service`.
- **Clean Teardown**: `ExecStop` safely shuts down containers and flushes SQLite WAL buffers.
- **Journal Integration**: Systemd captures stdout and stderr from docker compose commands into journald.
