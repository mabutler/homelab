# Phase 0 Research: Frigate NVR Pre-Arrival Setup for Two Cameras

**Feature**: `009-frigate-nvr-setup`  
**Date**: 2026-11-04  
**Spec**: [spec.md](./spec.md)

---

## 1. Container Image & Pinned Version Selection

- **Decision**: Use the upstream stable Frigate container image `ghcr.io/blakeblackshear/frigate:0.14.1` (standard amd64 image).
- **Rationale**:
  - Constitution Principle VII (*Stability-First & Annual Maintenance Cadence*) mandates pinning to battle-tested stable releases rather than `:stable` or `:latest` floating tags.
  - The standard `0.14.1` image bundles both Intel VAAPI/QSV media drivers (`iHD`) for hardware video decoding and the OpenVINO runtime with a default MobileNetV2 SSD model (`/openvino-model/ssdlite_mobilenet_v2.xml`) for AI object detection on the integrated Intel GPU.
  - Specialized variant tags (`-rocm`, `-tensorrt`) are unnecessary and heavier because the discrete AMD GPU is intentionally left untouched.
- **Alternatives Considered**:
  - `ghcr.io/blakeblackshear/frigate:stable` (floating tag): Rejected due to risk of unscheduled breaking changes across container pulls.
  - `ghcr.io/blakeblackshear/frigate:0.14.1-rocm`: Rejected because the user clarified that Frigate must use the integrated Intel UHD Graphics 770 iGPU (`00:02.0`) for both video decoding and OpenVINO object detection, leaving the discrete AMD Radeon RX 6700 XT untouched.

---

## 2. Hardware Video Decoding & AI Object Detection on Intel UHD Graphics 770 iGPU

- **Decision**:
  - Bind the host's Intel Alder Lake-S UHD Graphics 770 iGPU (`00:02.0`) into the container using deterministic PCI device paths under `/dev/dri/by-path/`:
    - `/dev/dri/by-path/pci-0000:00:02.0-render:/dev/dri/renderD128`
    - `/dev/dri/by-path/pci-0000:00:02.0-card:/dev/dri/card0`
  - Set `LIBVA_DRIVER_NAME=iHD` in the container environment and `ffmpeg.hwaccel_args: preset-vaapi` in `config.yml`.
  - Configure OpenVINO as the sole object detector (`detectors.ov: { type: openvino, device: GPU }` with `model: { path: /openvino-model/ssdlite_mobilenet_v2.xml, width: 300, height: 300, input_tensor: nhwc, input_pixel_format: bgr, labelmap_path: /openvino-model/coco_91cl_bkgr.txt }`).
  - Omit all Google Coral Edge TPU device mounts and detector configurations.
- **Rationale**:
  - On dual-GPU hosts (`00:02.0` Intel UHD Graphics 770 and `03:00.0` AMD Radeon RX 6700 XT), kernel enumeration order can shift `/dev/dri/renderD128` and `/dev/dri/renderD129` across kernel updates or BIOS changes. Mapping `/dev/dri/by-path/pci-0000:00:02.0-render` explicitly to `/dev/dri/renderD128` inside the container guarantees that Frigate always binds to the Intel iGPU and cannot touch the discrete AMD GPU.
  - Passing only the specific render/card devices avoids `privileged: true`, satisfying the Constitution's Least Privilege standard.
  - OpenVINO on Intel UHD 770 easily handles 2 cameras at 5 FPS detection with low power draw (~10–15 ms inference latency) without requiring a Coral TPU.
- **Alternatives Considered**:
  - Passing the entire `/dev/dri:/dev/dri` directory: Rejected because it exposes the discrete AMD GPU to the container and relies on volatile `renderD128` numbering.
  - CPU-only object detection (`type: cpu`): Rejected for production use because Frigate strongly discourages CPU detectors due to high thermal/CPU load; OpenVINO on the Intel iGPU provides dedicated hardware inference.

---

## 3. Pre-Arrival Two-Camera Staging & Zero-Camera Startup Health

- **Decision**:
  - Pre-configure `camera_1` and `camera_2` in `/opt/services/frigate/config/config.yml` with complete dual-stream (`detect` and `record`) definitions, object tracking (`person`, `car`), and retention policies (`7` days motion/continuous recordings, `14` days active object events/snapshots).
  - Set `enabled: false` on both `camera_1` and `camera_2` by default prior to physical camera arrival (configurable via Ansible defaults `frigate_camera_1_enabled: false` and `frigate_camera_2_enabled: false` or directly in `config.yml`).
  - Use Frigate's native `{FRIGATE_*}` environment variable substitution for camera stream URLs:
    - `{FRIGATE_CAMERA_1_RTSP_MAIN_URL}` & `{FRIGATE_CAMERA_1_RTSP_SUB_URL}`
    - `{FRIGATE_CAMERA_2_RTSP_MAIN_URL}` & `{FRIGATE_CAMERA_2_RTSP_SUB_URL}`
- **Rationale**:
  - In Frigate 0.14+, camera blocks with `enabled: false` are validated for schema correctness at startup, appear in the configuration structure, and allow the Frigate web UI, `/api/version`, and `/api/stats` endpoints to initialize cleanly with zero ffmpeg crash loops or log spam while cameras are still in transit.
  - Using `{FRIGATE_*}` environment variable substitution keeps `config.yml` completely free of credentials or IP addresses. When the cameras arrive, the operator only populates the RTSP URLs in the gitignored secrets file and flips `enabled: true`.
- **Alternatives Considered**:
  - Running a synthetic ffmpeg loopback stream container for two fake cameras 24/7 before arrival: Rejected because it wastes GPU/disk resources and writes dummy video files prior to delivery (violating YAGNI and Minimalist Footprint).
  - Leaving `cameras: {}` empty in `config.yml`: Rejected because it fails User Story 2 (FR-003), which requires `camera_1` and `camera_2` slots to be pre-structured with dual-stream `detect`/`record` roles and retention policies so onboarding takes under 5 minutes.

---

## 4. Tiered Storage Separation & Shared Memory Sizing

- **Decision**:
  - **Tier 0 Fast NVMe App Storage (`/opt/services/frigate`)**:
    - `/opt/services/frigate/config` → mounted at `/config` inside the container (stores `config.yml` and SQLite metadata database `frigate.db`).
    - `/opt/services/frigate/.env` (mode `0600`) & `/opt/services/frigate/.env.example` (mode `0644`).
    - `/opt/services/frigate/backups` (local staging for transactional SQLite `snapshot.sqlite3`).
  - **Tier 2 Dedicated Scratch Storage (`/mnt/scratch/frigate`)**:
    - `/mnt/scratch/frigate/media` → mounted at `/media/frigate` inside the container (stores `recordings/`, `clips/`, `exports/`).
  - **In-Memory Volatile Buffers**:
    - `shm_size: "256mb"` for `/dev/shm` frame buffers (Frigate recommends $\ge 64\text{ MB}$ per camera plus go2rtc/logs overhead; $256\text{ MB}$ comfortably supports 2–4 high-resolution 4K cameras).
    - `tmpfs` mount at `/tmp/cache` (`size=512m`) so ffmpeg segment concatenation occurs in RAM rather than causing SSD write amplification.
- **Rationale**:
  - Aligns strictly with the 3-tier storage architecture established in Phase 4 (`004-storage-pooling-resiliency`): SQLite queries remain responsive on NVMe, while 24/7 CCTV video streams write exclusively to `/mnt/scratch` (`/dev/sdb`, 916 GB) outside MergerFS (`/mnt/storage`) and SnapRAID parity calculation.
- **Alternatives Considered**:
  - Storing recordings under `/mnt/storage` (MergerFS): Strictly prohibited by FR-007 and Phase 4 storage architecture because continuous CCTV writes invalidate SnapRAID parity calculation.

---

## 5. Network Exposure & Access Control (LAN + Tailscale VPN Only)

- **Decision**:
  - Bind Frigate's internal HTTP UI/API port (`5000`), authenticated HTTPS UI port (`8971`), RTSP restream port (`8554`), and WebRTC ports (`8555/tcp`, `8555/udp`).
  - Restrict network ingress via `nftables` (`ansible/roles/firewall`) so Frigate ports are reachable **only** from:
    1. Loopback (`lo`, `127.0.0.1`) for local health checks and internal services.
    2. Tailscale VPN overlay interface (`tailscale0`, already accepted by rule `iifname "tailscale0" accept`).
    3. Trusted local LAN subnet (`192.168.4.0/24` via `firewall_allowed_subnets` rule).
  - Do **not** register Frigate on Tailscale Funnel (public port `443` remains exclusively bound to Vaultwarden).
- **Rationale**:
  - Satisfies FR-010 and Constitution Operational Standards (*Network Isolation & Least Privilege*): homeowners can view the Frigate dashboard and low-latency WebRTC streams seamlessly from any device on the home LAN (`192.168.4.0/24`) or via Tailscale VPN (`tailscale0`), while external/public internet packets are dropped at the firewall and never routed via Tailscale Funnel.
- **Alternatives Considered**:
  - Exposing Frigate via Tailscale Funnel: Explicitly prohibited by FR-010 and spec assumptions.
  - Binding `5000` only to `127.0.0.1` without LAN/VPN exposure: Would prevent authorized LAN and Tailscale devices from opening the Frigate web UI directly unless an additional proxy port was opened; allowing `192.168.4.0/24` and `tailscale0` in `nftables` while keeping public ingress dropped provides direct UI + WebRTC (`8555`) connectivity.

---

## 6. Offsite Backup Integration & Bulk Video Exclusion

- **Decision**:
  - Create `/etc/homelab/backup.d/20-frigate.sh` (`Contract: APP-BACKUP-V1`) in `ansible/roles/backup`:
    - `pre-backup`: Executes online `sqlite3 /opt/services/frigate/config/frigate.db "VACUUM INTO '/opt/services/frigate/backups/snapshot.sqlite3'"` and verifies `PRAGMA integrity_check;` equals `ok`.
    - `post-restore`: Restores `frigate.db` from `snapshot.sqlite3` if missing and ensures directory permissions.
  - Update `backup_exclude_patterns` in `ansible/roles/backup/defaults/main.yml` to exclude live SQLite database files under `/opt/services/*/config/*.db*`, `/opt/services/frigate/config/model_cache/**`, and explicitly exclude `/mnt/scratch/**` so zero bytes of raw CCTV footage are ever uploaded to Backblaze B2.
- **Rationale**:
  - Satisfies Constitution Principle V and FR-011: configuration (`/opt/services/frigate/config/config.yml`), secrets (`/opt/services/frigate/.env` and `/etc/homelab/vault.yml`), and the verified SQLite event database snapshot (`/opt/services/frigate/backups/snapshot.sqlite3`) are automatically captured in nightly encrypted Restic backups to Backblaze B2, while multi-gigabyte video recordings on `/mnt/scratch/frigate/media` are strictly excluded.
- **Alternatives Considered**:
  - Stopping the Frigate container during nightly backups: Rejected because stopping NVR services creates a surveillance blind spot every night at 02:30 AM; `sqlite3 ... VACUUM INTO` creates a consistent point-in-time snapshot online with zero downtime.
