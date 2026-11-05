# Contract: Frigate Service, Configuration & Hardware Acceleration (`FRIGATE-SERVICE-V1`)

**Feature**: `009-frigate-nvr-setup`  
**Date**: 2026-11-04  
**Requirements Covered**: FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-013

---

## 1. Directory & File Layout Contract

| Host Path | Owner:Group | Mode | Storage Tier | Purpose |
|---|---|---|---|---|
| `/opt/services/frigate` | `root:root` | `0755` | Tier 0 NVMe | Service root directory |
| `/opt/services/frigate/compose.yml` | `root:root` | `0644` | Tier 0 NVMe | Declarative Docker Compose manifest |
| `/opt/services/frigate/.env` | `root:root` | `0600` | Tier 0 NVMe | Isolated camera RTSP secret environment variables |
| `/opt/services/frigate/.env.example` | `root:root` | `0644` | Tier 0 NVMe | Sanitized reference template for camera RTSP variables |
| `/opt/services/frigate/config` | `root:root` | `0755` | Tier 0 NVMe | Frigate configuration & SQLite metadata directory (`frigate.db`) |
| `/opt/services/frigate/config/config.yml` | `root:root` | `0644` | Tier 0 NVMe | Frigate configuration file with OpenVINO + VAAPI + 2 camera slots |
| `/opt/services/frigate/backups` | `root:root` | `0750` | Tier 0 NVMe | Staging directory for transactional SQLite `snapshot.sqlite3` |
| `/mnt/scratch/frigate` | `root:storage` | `2775` | Tier 2 Scratch | Dedicated CCTV root on `/mnt/scratch` (`/dev/sdb`) |
| `/mnt/scratch/frigate/media` | `root:storage` | `2775` | Tier 2 Scratch | Mounted at `/media/frigate` for `recordings/`, `clips/`, `exports/` |

---

## 2. Docker Compose Contract (`/opt/services/frigate/compose.yml`)

```yaml
services:
  frigate:
    image: ghcr.io/blakeblackshear/frigate:0.14.1
    container_name: frigate
    restart: unless-stopped
    stop_grace_period: 30s
    shm_size: "256mb"
    devices:
      - /dev/dri/by-path/pci-0000:00:02.0-render:/dev/dri/renderD128
      - /dev/dri/by-path/pci-0000:00:02.0-card:/dev/dri/card0
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /opt/services/frigate/config:/config
      - /mnt/scratch/frigate/media:/media/frigate
      - type: tmpfs
        target: /tmp/cache
        tmpfs:
          size: 536870912
    env_file:
      - .env
    environment:
      - LIBVA_DRIVER_NAME=iHD
    ports:
      - "5000:5000"
      - "8971:8971"
      - "8554:8554"
      - "8555:8555/tcp"
      - "8555:8555/udp"
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:5000/api/version >/dev/null || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s
```

### Hardware Isolation Rules
- **Explicit iGPU Pass-Through**: Only `/dev/dri/by-path/pci-0000:00:02.0-render` and `/dev/dri/by-path/pci-0000:00:02.0-card` (Intel UHD Graphics 770) are mounted into the container.
- **Discrete AMD GPU Untouched**: `/dev/dri/by-path/pci-0000:03:00.0-*` (`renderD129`, AMD Radeon RX 6700 XT) is **never** passed into the container.
- **Zero Coral TPU Dependency**: No `/dev/bus/usb` or `/dev/apex_0` devices are mounted.

---

## 3. Systemd Lifecycle Unit Contract (`/etc/systemd/system/frigate.service`)

```ini
[Unit]
Description=Frigate NVR Service (Docker Compose)
Requires=docker.service local-fs.target
After=docker.service network-online.target local-fs.target
Wants=network-online.target
RequiresMountsFor=/opt/services /mnt/scratch

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/services/frigate
ExecStart=/usr/bin/docker compose up -d --remove-orphans
ExecStop=/usr/bin/docker compose down
ExecReload=/usr/bin/docker compose up -d --remove-orphans
TimeoutStartSec=180
TimeoutStopSec=60

[Install]
WantedBy=multi-user.target
```

---

## 4. Frigate Configuration Contract (`/opt/services/frigate/config/config.yml`)

```yaml
mqtt:
  enabled: false

detectors:
  ov:
    type: openvino
    device: GPU

model:
  width: 300
  height: 300
  input_tensor: nhwc
  input_pixel_format: bgr
  path: /openvino-model/ssdlite_mobilenet_v2.xml
  labelmap_path: /openvino-model/coco_91cl_bkgr.txt

ffmpeg:
  hwaccel_args: preset-vaapi

detect:
  enabled: true
  width: 1280
  height: 720
  fps: 5

objects:
  track:
    - person
    - car

record:
  enabled: true
  retain:
    days: 7
    mode: motion
  events:
    retain:
      default: 14
      mode: active_objects

snapshots:
  enabled: true
  retain:
    default: 14

cameras:
  camera_1:
    enabled: false
    ffmpeg:
      inputs:
        - path: "{FRIGATE_CAMERA_1_RTSP_SUB_URL}"
          roles:
            - detect
        - path: "{FRIGATE_CAMERA_1_RTSP_MAIN_URL}"
          roles:
            - record
  camera_2:
    enabled: false
    ffmpeg:
      inputs:
        - path: "{FRIGATE_CAMERA_2_RTSP_SUB_URL}"
          roles:
            - detect
        - path: "{FRIGATE_CAMERA_2_RTSP_MAIN_URL}"
          roles:
            - record
```

---

## 5. Secret Environment Template Contract (`/opt/services/frigate/.env.example`)

```dotenv
# Frigate NVR Camera RTSP Credentials & Stream Endpoints
# Populate real credentials in /opt/services/frigate/.env (mode 0600) or ansible/inventory/group_vars/all/vault.yml
FRIGATE_CAMERA_1_RTSP_MAIN_URL="rtsp://admin:CHANGE_ME_PASSWORD@192.168.4.201:554/h264Preview_01_main"
FRIGATE_CAMERA_1_RTSP_SUB_URL="rtsp://admin:CHANGE_ME_PASSWORD@192.168.4.201:554/h264Preview_01_sub"
FRIGATE_CAMERA_2_RTSP_MAIN_URL="rtsp://admin:CHANGE_ME_PASSWORD@192.168.4.202:554/h264Preview_01_main"
FRIGATE_CAMERA_2_RTSP_SUB_URL="rtsp://admin:CHANGE_ME_PASSWORD@192.168.4.202:554/h264Preview_01_sub"
```
