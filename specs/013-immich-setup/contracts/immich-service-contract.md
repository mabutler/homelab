# Contract: Immich Service, Compose & Hardware Acceleration (`IMMICH-SERVICE-V1`)

**Feature**: `013-immich-setup`  
**Date**: 2026-11-06  
**Requirements Covered**: FR-001, FR-002, FR-003, FR-004, FR-005, FR-009, FR-010

---

## 1. Directory & File Layout Contract

| Host Path | Owner:Group | Mode | Storage Tier | Purpose |
|---|---|---|---|---|
| `/opt/services/immich` | `root:root` | `0755` | Tier 0 NVMe | Immich service root directory |
| `/opt/services/immich/compose.yml` | `root:root` | `0644` | Tier 0 NVMe | Declarative Docker Compose manifest |
| `/opt/services/immich/.env` | `root:root` | `0600` | Tier 0 NVMe | Isolated database credentials & environment variables |
| `/opt/services/immich/.env.example` | `root:root` | `0644` | Tier 0 NVMe | Sanitized template for environment variables |
| `/opt/services/immich/data` | `root:root` | `0755` | Tier 0 NVMe | Root for fast-NVMe application state |
| `/opt/services/immich/data/postgres` | `999:999` | `0700` | Tier 0 NVMe | PostgreSQL database cluster (`pgvector`) |
| `/opt/services/immich/data/thumbs` | `1000:1001` | `0755` | Tier 0 NVMe | Pre-generated image & video thumbnails |
| `/opt/services/immich/data/model-cache` | `1000:1001` | `0755` | Tier 0 NVMe | Downloaded machine learning models (CLIP, Facial) |
| `/opt/services/immich/data/profile` | `1000:1001` | `0755` | Tier 0 NVMe | User profile images |
| `/opt/services/immich/backups` | `root:root` | `0750` | Tier 0 NVMe | Staging directory for transactional `pg_dump` snapshots |
| `/mnt/storage/media/photos` | `admin:storage` | `2775` | Tier 1 Bulk | Mass storage library root on MergerFS |
| `/mnt/storage/media/photos/library` | `admin:storage` | `2775` | Tier 1 Bulk | Immutable full-resolution photo and video assets |
| `/mnt/storage/media/photos/upload` | `admin:storage` | `2775` | Tier 1 Bulk | Temporary multi-part upload staging buffer |
| `/mnt/storage/media/photos/encoded-video` | `admin:storage` | `2775` | Tier 1 Bulk | Transcoded MP4 video streaming cache |

---

## 2. Docker Compose Manifest Contract (`/opt/services/immich/compose.yml`)

```yaml
# Docker Compose manifest for Immich Photo Management Platform
# Managed by Ansible - homelab2
# Contract: IMMICH-SERVICE-V1

services:
  immich-server:
    container_name: immich_server
    image: ghcr.io/immich-app/immich-server:${IMMICH_VERSION:-v1.118.2}
    restart: unless-stopped
    stop_grace_period: 30s
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - ${UPLOAD_LOCATION:-/mnt/storage/media/photos}:/usr/src/app/upload
      - ${DATA_LOCATION:-/opt/services/immich/data}/thumbs:/usr/src/app/upload/thumbs
      - ${DATA_LOCATION:-/opt/services/immich/data}/profile:/usr/src/app/upload/profile
      - ${BACKUP_LOCATION:-/opt/services/immich/backups}:/backups
    env_file:
      - .env
    environment:
      - NODE_ENV=production
      - LIBVA_DRIVER_NAME=iHD
    ports:
      - "127.0.0.1:2283:2283"
    devices:
      - /dev/dri/by-path/pci-0000:00:02.0-render:/dev/dri/renderD128
      - /dev/dri/by-path/pci-0000:00:02.0-card:/dev/dri/card0
    depends_on:
      redis:
        condition: service_healthy
      database:
        condition: service_healthy
      immich-machine-learning:
        condition: service_started
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://localhost:2283/api/server/ping"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 45s

  immich-machine-learning:
    container_name: immich_machine_learning
    image: ghcr.io/immich-app/immich-machine-learning:${IMMICH_VERSION:-v1.118.2}
    restart: unless-stopped
    stop_grace_period: 30s
    volumes:
      - ${DATA_LOCATION:-/opt/services/immich/data}/model-cache:/cache
    env_file:
      - .env
    environment:
      - NODE_ENV=production
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://localhost:3003/ping"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  redis:
    container_name: immich_redis
    image: docker.io/redis:${REDIS_VERSION:-6.2-alpine}
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 10s

  database:
    container_name: immich_postgres
    image: docker.io/tensorchord/pgvecto-rs:${DB_VERSION:-pg16-v0.2.1}
    restart: unless-stopped
    stop_grace_period: 60s
    environment:
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_USER: ${DB_USERNAME:-immich}
      POSTGRES_DB: ${DB_DATABASE_NAME:-immich}
      POSTGRES_INITDB_ARGS: '--data-checksums'
    volumes:
      - ${DATA_LOCATION:-/opt/services/immich/data}/postgres:/var/lib/postgresql/data
      - ${BACKUP_LOCATION:-/opt/services/immich/backups}:/backups
    healthcheck:
      test: ["CMD-SHELL", "pg_isready --dbname='${DB_DATABASE_NAME:-immich}' --username='${DB_USERNAME:-immich}' || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 20s
```

### Hardware Isolation Rules
- **Explicit iGPU Pass-Through**: Only `/dev/dri/by-path/pci-0000:00:02.0-render` and `/dev/dri/by-path/pci-0000:00:02.0-card` (Intel UHD Graphics 770) are mounted into the server container.
- **Discrete AMD GPU Isolation**: The discrete AMD Radeon RX 6700 XT (`03:00.0`, `/dev/dri/by-path/pci-0000:03:00.0-*`) is **strictly forbidden** from container mounts.
- **Loopback Ingress**: `immich-server` binds port 2283 strictly to `127.0.0.1:2283`. No container ports are published to `0.0.0.0`.

---

## 3. Systemd Unit Contract (`/etc/systemd/system/immich.service`)

```ini
[Unit]
Description=Immich Photo Management Platform (Docker Compose)
Requires=docker.service local-fs.target
After=docker.service network-online.target local-fs.target
Wants=network-online.target
RequiresMountsFor=/opt/services /mnt/storage

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/services/immich
ExecStart=/usr/bin/docker compose up -d --remove-orphans
ExecStop=/usr/bin/docker compose down
ExecReload=/usr/bin/docker compose up -d --remove-orphans
TimeoutStartSec=300
TimeoutStopSec=90

[Install]
WantedBy=multi-user.target
```
