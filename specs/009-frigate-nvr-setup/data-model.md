# Phase 1 Data Model: Frigate NVR Pre-Arrival Setup for Two Cameras

**Feature**: `009-frigate-nvr-setup`  
**Date**: 2026-11-04  
**Spec**: [spec.md](./spec.md) | **Research**: [research.md](./research.md)

---

## 1. Entity Overview

```
+-------------------------------------------------------------------+
|                   Frigate NVR Service Instance                    |
|  - systemd unit: frigate.service                                  |
|  - container: ghcr.io/blakeblackshear/frigate:0.14.1              |
|  - iGPU device: /dev/dri/by-path/pci-0000:00:02.0-render          |
+-------------------------------------------------------------------+
         |                                      |
         | reads / substitutes                  | mounts tiered storage
         v                                      v
+----------------------------------+   +------------------------------------+
|     Camera Secret Profile        |   |      Storage Tier Allocation       |
|  (/opt/services/frigate/.env)    |   |  - Tier 0 NVMe: /opt/services/...  |
|  - FRIGATE_CAMERA_1_RTSP_MAIN_URL|   |    (config.yml, frigate.db,        |
|  - FRIGATE_CAMERA_1_RTSP_SUB_URL |   |     backups/snapshot.sqlite3)      |
|  - FRIGATE_CAMERA_2_RTSP_MAIN_URL|   |  - Tier 2 Scratch: /mnt/scratch/.. |
|  - FRIGATE_CAMERA_2_RTSP_SUB_URL |   |    (recordings, clips, exports)    |
+----------------------------------+   +------------------------------------+
         |                                      |
         +------------------+-------------------+
                            | configures
                            v
         +--------------------------------------+
         |   Camera Slot (camera_1, camera_2)   |
         |  - enabled: false (pre-arrival)      |
         |  - detect stream (720p @ 5 fps)      |
         |  - record stream (main resolution)   |
         |  - objects: [person, car]            |
         |  - retain: 7d motion / 14d events    |
         +--------------------------------------+
```

---

## 2. Entities & Schema Definitions

### 2.1 Frigate NVR Service Instance

Represents the containerized Frigate workload managed via systemd and Docker Compose.

| Field / Attribute | Type / Value | Storage / Location | Validation Rule |
|---|---|---|---|
| `frigate_service_name` | `string` (`"frigate"`) | `ansible/roles/frigate/defaults/main.yml` | Must match container name and systemd service unit (`frigate.service`) |
| `frigate_image_tag` | `string` (`"ghcr.io/blakeblackshear/frigate:0.14.1"`) | `ansible/roles/frigate/defaults/main.yml` | Must be pinned to an explicit semantic version tag (no `:latest` or `:stable`) |
| `frigate_igpu_render_device` | `path` (`"/dev/dri/by-path/pci-0000:00:02.0-render"`) | Host PCI DRM path | Must exist as a character device symlink resolving to Intel UHD Graphics 770 (`00:02.0`) |
| `frigate_igpu_card_device` | `path` (`"/dev/dri/by-path/pci-0000:00:02.0-card"`) | Host PCI DRM path | Must exist as a character device symlink resolving to Intel UHD Graphics 770 (`00:02.0`) |
| `frigate_shm_size` | `string` (`"256mb"`) | `compose.yml` (`shm_size`) | Must be $\ge 128\text{ MB}$ to support $\ge 2$ high-resolution dual-stream cameras without `/dev/shm` exhaustion |
| `frigate_tmpfs_cache_size` | `string` (`"512m"`) | `compose.yml` (`/tmp/cache`) | Volatile RAM cache for recording segment assembly |
| `frigate_http_port` | `integer` (`5000`) | Host & Container TCP | Reachable on loopback, `192.168.4.0/24`, and `tailscale0`; blocked from public internet |
| `frigate_auth_port` | `integer` (`8971`) | Host & Container TCP | Reachable on loopback, `192.168.4.0/24`, and `tailscale0` |
| `frigate_rtsp_port` | `integer` (`8554`) | Host & Container TCP | go2rtc RTSP restream port |
| `frigate_webrtc_port` | `integer` (`8555`) | Host & Container TCP/UDP | go2rtc WebRTC live-view port |

---

### 2.2 Hardware Accelerator & Detector Profile

Defines the video decoding and AI object detection pipeline inside `/opt/services/frigate/config/config.yml`.

| Field / Attribute | Value | Purpose / Validation Rule |
|---|---|---|
| `LIBVA_DRIVER_NAME` | `"iHD"` | Environment variable selecting the Intel Media Driver for Alder Lake-S UHD Graphics 770 |
| `ffmpeg.hwaccel_args` | `"preset-vaapi"` | Instructs Frigate ffmpeg workers to decode H.264/H.265 streams on the Intel iGPU via VAAPI |
| `detectors.ov.type` | `"openvino"` | Selects OpenVINO runtime (no Coral Edge TPU dependency) |
| `detectors.ov.device` | `"GPU"` | Targets the integrated Intel GPU mapped at `/dev/dri/renderD128` inside the container |
| `model.path` | `"/openvino-model/ssdlite_mobilenet_v2.xml"` | Built-in MobileNetV2 SSD OpenVINO model inside `frigate:0.14.1` |
| `model.width` / `model.height` | `300` / `300` | Input tensor dimensions for `ssdlite_mobilenet_v2` |
| `model.input_tensor` / `input_pixel_format` | `"nhwc"` / `"bgr"` | Required input layout for the built-in OpenVINO MobileNetV2 model |
| `model.labelmap_path` | `"/openvino-model/coco_91cl_bkgr.txt"` | COCO 91-class label map bundled in container |

---

### 2.3 Camera Slot (`camera_1`, `camera_2`)

Pre-staged camera configuration blocks in `/opt/services/frigate/config/config.yml`.

| Field / Attribute | `camera_1` Default | `camera_2` Default | Validation Rule |
|---|---|---|---|
| `enabled` | `false` (`frigate_camera_1_enabled`) | `false` (`frigate_camera_2_enabled`) | Defaults to `false` pre-arrival so Frigate runs cleanly with zero connection errors; set to `true` upon camera installation |
| `ffmpeg.inputs[0].path` | `"{FRIGATE_CAMERA_1_RTSP_SUB_URL}"` | `"{FRIGATE_CAMERA_2_RTSP_SUB_URL}"` | Substituted at runtime from `/opt/services/frigate/.env`; assigned `roles: [detect]` |
| `ffmpeg.inputs[1].path` | `"{FRIGATE_CAMERA_1_RTSP_MAIN_URL}"` | `"{FRIGATE_CAMERA_2_RTSP_MAIN_URL}"` | Substituted at runtime from `/opt/services/frigate/.env`; assigned `roles: [record]` |
| `detect.enabled` | `true` | `true` | Enables object detection pipeline once the camera slot itself is enabled |
| `detect.width` x `detect.height` | `1280` x `720` | `1280` x `720` | Standard 720p sub-stream detection resolution |
| `detect.fps` | `5` | `5` | 5 FPS detection sampling rate recommended by Frigate |
| `objects.track` | `["person", "car"]` | `["person", "car"]` | Default tracked object classes |
| `record.enabled` | `true` | `true` | Enables recording once the camera slot is enabled |
| `record.retain.days` | `7` | `7` | Retains general motion/continuous recordings for 7 days (FR-009) |
| `record.retain.mode` | `"motion"` | `"motion"` | Retains segments containing motion |
| `record.events.retain.default` | `14` | `14` | Retains tracked detection event recordings for 14 days (FR-009) |
| `record.events.retain.mode` | `"active_objects"` | `"active_objects"` | Retains segments where tracked objects were active |
| `snapshots.enabled` | `true` | `true` | Captures JPEG snapshots for detection events |
| `snapshots.retain.default` | `14` | `14` | Retains event snapshots for 14 days |

---

### 2.4 Camera Secret Profile

Gitignored credential store isolating camera RTSP URLs and credentials from version control (FR-005, Principle IV).

| Variable Name | Source in `vault.yml` | Destination in `/opt/services/frigate/.env` | Default Placeholder (`.example`) |
|---|---|---|---|
| `FRIGATE_CAMERA_1_RTSP_MAIN_URL` | `vault_frigate_camera_1_rtsp_main_url` | `FRIGATE_CAMERA_1_RTSP_MAIN_URL=...` | `"rtsp://admin:CHANGE_ME_PASSWORD@192.168.4.201:554/h264Preview_01_main"` |
| `FRIGATE_CAMERA_1_RTSP_SUB_URL` | `vault_frigate_camera_1_rtsp_sub_url` | `FRIGATE_CAMERA_1_RTSP_SUB_URL=...` | `"rtsp://admin:CHANGE_ME_PASSWORD@192.168.4.201:554/h264Preview_01_sub"` |
| `FRIGATE_CAMERA_2_RTSP_MAIN_URL` | `vault_frigate_camera_2_rtsp_main_url` | `FRIGATE_CAMERA_2_RTSP_MAIN_URL=...` | `"rtsp://admin:CHANGE_ME_PASSWORD@192.168.4.202:554/h264Preview_01_main"` |
| `FRIGATE_CAMERA_2_RTSP_SUB_URL` | `vault_frigate_camera_2_rtsp_sub_url` | `FRIGATE_CAMERA_2_RTSP_SUB_URL=...` | `"rtsp://admin:CHANGE_ME_PASSWORD@192.168.4.202:554/h264Preview_01_sub"` |

*Validation Rules*:
- `/opt/services/frigate/.env` MUST have file mode `0600` (`root:root`).
- `/opt/services/frigate/.env.example` and `ansible/inventory/group_vars/all/vault.yml.example` MUST contain only sanitized placeholder strings.
- Zero real passwords or credentials may appear in git-tracked files.

---

### 2.5 Storage Tier & Backup Artifacts

| Path | Storage Tier | Container Mount | Backup Policy (Restic -> Backblaze B2) |
|---|---|---|---|
| `/opt/services/frigate/config/config.yml` | Tier 0 NVMe (`/opt/services`) | `/config/config.yml` | **Included** directly in `/opt/services` |
| `/opt/services/frigate/.env` | Tier 0 NVMe (`/opt/services`) | `env_file` | **Included** directly in `/opt/services` (and source `vault.yml` in `/etc/homelab/vault.yml`) |
| `/opt/services/frigate/config/frigate.db` | Tier 0 NVMe (`/opt/services`) | `/config/frigate.db` | Live `.db`/`.db-wal`/`.db-shm` **Excluded**; backed up via transactional `VACUUM INTO` snapshot |
| `/opt/services/frigate/backups/snapshot.sqlite3` | Tier 0 NVMe (`/opt/services`) | Host-only backup staging | **Included** in `/opt/services`; generated by `/etc/homelab/backup.d/20-frigate.sh` (`PRAGMA integrity_check;`) |
| `/opt/services/frigate/config/model_cache` | Tier 0 NVMe (`/opt/services`) | `/config/model_cache` | **Excluded** (regenerable OpenVINO compiled kernel cache) |
| `/mnt/scratch/frigate/media` | Tier 2 Scratch (`/mnt/scratch`, `/dev/sdb`) | `/media/frigate` | **Strictly Excluded** from both SnapRAID parity and Restic offsite backups |

---

## 3. Lifecycle State Transitions

### 3.1 Camera Slot Lifecycle

```
+-------------------------------------------------------------------+
| State 1: PRE_ARRIVAL_STAGED (Default on initial deployment)       |
| - camera_1.enabled = false, camera_2.enabled = false              |
| - .env contains placeholder RTSP URLs                             |
| - Frigate UI & API healthy; 0 ffmpeg connection errors in logs    |
+-------------------------------------------------------------------+
                                 |
                                 | Physical cameras delivered & connected to LAN
                                 | Operator populates RTSP URLs in .env / vault.yml
                                 | and sets enabled: true for camera_1 & camera_2
                                 v
+-------------------------------------------------------------------+
| State 2: ACTIVE_MONITORING                                        |
| - ffmpeg decodes sub-stream via Intel UHD 770 VAAPI               |
| - OpenVINO detector runs inference on Intel UHD 770 iGPU          |
| - Continuous/motion segments & clips written to /mnt/scratch      |
| - Event metadata written to /opt/services/frigate/config/frigate.db|
+-------------------------------------------------------------------+
         |                                               ^
         | Camera temporarily unplugged / power loss     | Camera returns online
         v                                               |
+-------------------------------------------------------------------+
| State 3: STREAM_RECONNECTING                                      |
| - Remaining camera continues uninterrupted recording & detection  |
| - Frigate retries offline camera RTSP connection with backoff     |
+-------------------------------------------------------------------+
```

### 3.2 Recording Segment Retention Lifecycle

1. **Ingest (`IN_MEMORY_CACHE`)**: Incoming RTSP video frames are written to tmpfs `/tmp/cache` in RAM.
2. **Segment Flush (`SCRATCH_ACTIVE`)**: Completed recording segments, event clips, and snapshots are moved to `/mnt/scratch/frigate/media/{recordings,clips}`.
3. **Retention Pruning (`EXPIRED_DELETED`)**:
   - Standard motion/continuous segments older than `7` days are automatically deleted by Frigate's storage maintainer.
   - Tracked object event clips and snapshots older than `14` days are automatically deleted.
   - If `/mnt/scratch` approaches capacity early, Frigate automatically prunes the oldest recordings to maintain free space.
