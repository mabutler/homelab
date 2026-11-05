# Implementation Plan: Frigate NVR Pre-Arrival Setup for Two Cameras

**Branch**: `009-frigate-nvr-setup` | **Date**: 2026-11-04 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/009-frigate-nvr-setup/spec.md`

---

## Summary

Deploy the Frigate NVR service (`ghcr.io/blakeblackshear/frigate:0.14.1`) on `homelab2` ahead of the physical delivery of two security cameras so the surveillance platform is operational, hardware-accelerated, backed up, and verified now, while ready for < 5-minute camera onboarding upon arrival. The technical approach uses an isolated Ansible role (`ansible/roles/frigate`) managing a Docker Compose stack via systemd (`frigate.service`), binds the host's integrated Intel UHD Graphics 770 iGPU (`00:02.0`) via stable PCI device paths (`/dev/dri/by-path/pci-0000:00:02.0-render`) for both VAAPI video decoding and OpenVINO AI object detection (leaving the discrete AMD Radeon RX 6700 XT untouched and requiring zero Coral TPU hardware), pre-stages `camera_1` and `camera_2` dual-stream (`detect` + `record`) definitions with `enabled: false` and isolated `{FRIGATE_*}` secret placeholders in `/opt/services/frigate/.env`, separates application metadata (`/opt/services/frigate/config`) from high-churn CCTV recordings (`/mnt/scratch/frigate/media`), restricts web/API/WebRTC ingress to LAN (`192.168.4.0/24`) and Tailscale (`tailscale0`), and integrates online SQLite `VACUUM INTO` snapshots into the Restic Backblaze B2 backup pipeline while excluding `/mnt/scratch`.

---

## Technical Context

**Language/Version**:
- Container Workload: Frigate NVR `0.14.1` (`ghcr.io/blakeblackshear/frigate:0.14.1`)
- Automation & Tooling: Ansible 2.16+, POSIX Shell / Bash 5.2+, PowerShell 7+, SQLite 3.45+

**Primary Dependencies**:
- Container Runtime: Docker CE & Docker Compose v2 (`ansible/roles/docker`)
- Hardware Acceleration: Intel Media Driver (`LIBVA_DRIVER_NAME=iHD`, VAAPI) & OpenVINO GPU detector on Intel Alder Lake-S UHD Graphics 770 (`pci-0000:00:02.0`)
- Process Supervision: systemd (`frigate.service`)
- Firewall & Overlay Networking: `nftables` (`ansible/roles/firewall`) & Tailscale (`tailscale0`)
- Backup Pipeline: Restic + Backblaze B2 (`ansible/roles/backup`, `/etc/homelab/backup.d/20-frigate.sh`)

**Storage**:
- Tier 0 Fast NVMe App Storage (`/opt/services/frigate`): `compose.yml`, `.env` (`0600`), `.env.example`, `config/config.yml`, SQLite metadata database `config/frigate.db`, and transactional backup staging `backups/snapshot.sqlite3`
- Tier 2 Dedicated Scratch Storage (`/mnt/scratch/frigate/media` on `/dev/sdb`, 916 GB): continuous/motion recordings (`7` days retention), detection clips (`14` days retention), and snapshots (`14` days retention), strictly outside MergerFS (`/mnt/storage`) and SnapRAID parity
- Volatile In-Memory Buffers: `shm_size: "256mb"` (`/dev/shm`) and `512 MB` `tmpfs` at `/tmp/cache`

**Testing**:
- Static Analysis & Linting: `ansible-lint`, `shellcheck`, YAML/JSON syntax checks
- Automated Acceptance Suite: `scripts/verify-phase5-frigate.sh` (`FRG-01` through `FRG-09`), `scripts/verify-phase5-frigate.ps1`, and `ansible/playbooks/verify-phase5-frigate.yml` (integrated into `ansible/playbooks/verify.yml`)

**Target Platform**:
- Arch Linux x86_64 host (`homelab2`) with Intel UHD Graphics 770 iGPU (`00:02.0`) and discrete AMD Radeon RX 6700 XT (`03:00.0`)

**Project Type**:
- Infrastructure-as-Code (Ansible roles, playbooks, backup hooks, and verification scripts) for a containerized NVR application service

**Performance Goals**:
- Frigate HTTP API (`/api/version`, `/api/stats`) and Web UI respond with HTTP 200 in `< 2` seconds while zero physical cameras are connected (SC-001)
- Continuous 24-hour pre-arrival operation with `0` unexpected container restarts and `0` unhandled camera connection crash loops (SC-002)
- OpenVINO iGPU object detection inference latency `< 25 ms` per frame across two 720p @ 5 FPS detection sub-streams

**Constraints**:
- Zero Coral Edge TPU hardware present or configured; discrete AMD GPU (`03:00.0`) must remain untouched by Frigate (FR-013)
- Zero real camera credentials, RTSP passwords, or private hostnames in git; real secrets live exclusively in gitignored `vault.yml` and `/opt/services/frigate/.env` (`0600`), backed up via Restic to Backblaze B2 (FR-005, Principle IV)
- Zero bytes of CCTV recordings written to MergerFS/SnapRAID parity arrays or uploaded to Backblaze B2 offsite backups (FR-007, FR-011, SC-004)
- Web UI and API accessible only on loopback, local LAN (`192.168.4.0/24`), and Tailscale VPN (`tailscale0`); never exposed via public Tailscale Funnel (FR-010)

**Scale/Scope**:
- Pre-staged for 2 dual-stream (`detect` + `record`) network cameras (`camera_1` and `camera_2`) with headroom in `/dev/shm` (`256 MB`) and `/mnt/scratch` (`916 GB`) for future household expansion

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked and confirmed post-Phase 1 design.*

| Principle / Gate | Compliance Analysis | Status |
|---|---|---|
| **I. Pragmatic Declarative-First Automation** | Frigate directory layout, configuration rendering, Docker Compose manifest, systemd unit, firewall rules, and backup hook are declared via Ansible roles (`frigate`, `firewall`, `backup`). Transactional SQLite snapshotting and acceptance verification use modular, contract-backed shell scripts (`20-frigate.sh`, `verify-phase5-frigate.sh`). | **PASS** |
| **II. Strict Idempotency & Safe Convergence** | All Ansible tasks use idempotent modules (`file`, `template`, `systemd`, `assert`). Re-running `frigate.yml` or `site.yml` against a converged host produces `changed=0` without restarting healthy containers. | **PASS** |
| **III. Automated Verification & Acceptance Gates** | 9 automated verification checks (`FRG-01` through `FRG-09` in [verification-contract.md](./contracts/verification-contract.md)) verify service health, `/api/version` & `/api/stats` telemetry, iGPU PCI device isolation, camera slot staging, secret permissions, tiered storage mounts, firewall/Funnel isolation, backup hook execution, and journald logging. | **PASS** |
| **IV. Zero Secrets in Version Control & Isolated Configuration** | Camera RTSP credentials are stored only in gitignored `ansible/inventory/group_vars/all/vault.yml` and rendered to `/opt/services/frigate/.env` (`0600`). Committed files (`vault.yml.example`, `env.example`, `config.yml.j2`) use `{FRIGATE_*}` environment placeholders and sanitized examples only. | **PASS** |
| **V. Disaster Recovery & Backup by Design** | `/etc/homelab/backup.d/20-frigate.sh` executes online `sqlite3 ... VACUUM INTO` and `PRAGMA integrity_check;` prior to each Restic snapshot. `/opt/services/frigate` (config, `.env`, and DB snapshot) and `/etc/homelab/vault.yml` are backed up to Backblaze B2, while `/mnt/scratch` is explicitly excluded. | **PASS** |
| **VI. Modular & Decoupled Architecture** | Frigate runs in its own isolated Compose stack (`/opt/services/frigate`) and systemd unit (`frigate.service`). Starting, stopping, or updating Frigate has zero impact on Vaultwarden, Caddy, or storage services. | **PASS** |
| **VII. Stability-First & Annual Maintenance Cadence** | Image is pinned to upstream stable release `ghcr.io/blakeblackshear/frigate:0.14.1`. Recording retention (`7` days motion, `14` days events) is automated by Frigate with zero manual maintenance toil. | **PASS** |

**Gate Evaluation**: **PASS** (Pre-Phase 0 and Post-Phase 1). Zero constitutional violations.

---

## Project Structure

### Documentation (this feature)

```text
specs/009-frigate-nvr-setup/
├── spec.md                              # Feature specification
├── plan.md                              # This implementation plan
├── research.md                          # Phase 0 architectural decisions & research findings
├── data-model.md                        # Phase 1 entity schemas, storage mapping & state lifecycle
├── quickstart.md                        # Phase 1 deployment, validation & <5m camera onboarding guide
├── contracts/                           # Phase 1 explicit interface & verification contracts
│   ├── frigate-service-contract.md      # Compose, systemd, iGPU PCI mapping, config.yml & .env contract
│   ├── backup-restore-contract.md       # 20-frigate.sh SQLite snapshot hook & Restic exclusion contract
│   ├── network-ingress-contract.md      # LAN + Tailscale nftables access & zero-Funnel contract
│   └── verification-contract.md         # Automated acceptance assertions FRG-01 through FRG-09
├── checklists/
│   └── requirements.md                  # Specification quality checklist
└── tasks.md                             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
ansible/
├── inventory/
│   └── group_vars/
│       └── all/
│           ├── vars.yml                 # Non-sensitive Frigate defaults (ports, retention, enabled flags)
│           └── vault.yml.example        # Sanitized camera RTSP URL secret placeholders
├── playbooks/
│   ├── site.yml                         # Master convergence playbook (includes frigate role)
│   ├── frigate.yml                      # Dedicated Phase 5 Frigate deployment playbook
│   ├── verify-phase5-frigate.yml        # Dedicated Phase 5 Frigate acceptance verification playbook
│   └── verify.yml                       # Master platform verification playbook (imports verify-phase5-frigate.yml)
└── roles/
    ├── frigate/
    │   ├── defaults/
    │   │   └── main.yml                 # Pinned image, paths, shm/tmpfs sizing, iGPU paths, camera defaults
    │   ├── files/
    │   │   └── env.example              # Committed .env.example template for camera RTSP URLs
    │   ├── handlers/
    │   │   └── main.yml                 # Systemd daemon-reload and Frigate restart handlers
    │   ├── tasks/
    │   │   ├── main.yml                 # Role task orchestrator
    │   │   ├── preflight.yml            # Assert Intel iGPU PCI device & /mnt/scratch mount exist
    │   │   ├── layout.yml               # Create /opt/services/frigate/* and /mnt/scratch/frigate/media
    │   │   ├── config.yml               # Render .env (0600), .env.example, config.yml, and compose.yml
    │   │   └── service.yml              # Deploy and start frigate.service systemd unit
    │   └── templates/
    │       ├── compose.yml.j2           # Docker Compose manifest with Intel iGPU PCI pass-through
    │       ├── config.yml.j2            # Frigate config with OpenVINO GPU, VAAPI, and camera_1/camera_2
    │       ├── env.j2                   # Isolated FRIGATE_CAMERA_*_RTSP_* environment variables
    │       └── frigate.service.j2       # Systemd unit supervising Frigate Docker Compose stack
    ├── firewall/
    │   ├── defaults/
    │   │   └── main.yml                 # Add LAN-allowed Frigate TCP/UDP ports (5000, 8971, 8554, 8555)
    │   └── templates/
    │       └── nftables.conf.j2         # Permit trusted LAN subnets to reach Frigate ports
    └── backup/
        ├── defaults/
        │   └── main.yml                 # Exclude live Frigate .db/.db-wal/.db-shm, model_cache, and /mnt/scratch
        ├── tasks/
        │   └── hooks.yml                # Deploy /etc/homelab/backup.d/20-frigate.sh (0750)
        └── templates/
            └── 20-frigate.sh.j2         # Online SQLite VACUUM INTO snapshot & integrity check hook

scripts/
├── apply-phase5-frigate.sh              # Bash convergence wrapper for Frigate deployment
├── apply-phase5-frigate.ps1             # PowerShell convergence wrapper for Frigate deployment
├── verify-phase5-frigate.sh             # Target host acceptance test suite (FRG-01 to FRG-09)
└── verify-phase5-frigate.ps1            # Workstation acceptance test wrapper
```

**Structure Decision**:
- Follows the established `homelab2` Phase 5 application architecture (`ansible/roles/frigate`, `ansible/playbooks/frigate.yml`, `ansible/playbooks/verify-phase5-frigate.yml`, and `scripts/*-phase5-frigate.*`).
- Integrates cleanly with existing `firewall` and `backup` roles without introducing redundant daemons or custom container images.

---

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| *(None)* | All 7 Constitutional Principles pass unconditionally. | N/A |
