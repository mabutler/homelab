# Feature Specification: Frigate NVR Pre-Arrival Setup for Two Cameras

**Feature Branch**: `009-frigate-nvr-setup`

**Created**: 2026-11-04

**Status**: Draft

**Input**: User description: "Setup Frigate. I'm starting with just two cameras that are ordered, but not delivered yet. I want the software ready for them when they arrive"

## Clarifications

### Session 2026-11-04

- Q: Hardware acceleration scope (Coral TPU vs. host CPU/GPU) → A: No Coral TPU is present or planned; Frigate must use only the host's existing CPU and GPU resources for video decoding and AI object detection.
- Q: Which host GPU/CPU combination should Frigate use for video stream decoding and AI object detection? (FR-013) → A: Option A — Use the integrated Intel UHD Graphics 770 iGPU for both hardware video decoding and AI object detection (OpenVINO), leaving the discrete AMD Radeon RX 6700 XT GPU untouched (with option to re-evaluate if performance drops).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Operational Pre-Arrival NVR Service & Dashboard Access (Priority: P1)

As a homeowner awaiting the delivery of two security cameras, I want the Network Video Recorder (NVR) software deployed, running cleanly, and reachable through its web interface right now, so that the system is fully operational and verified before the physical cameras arrive.

**Why this priority**: The primary goal is having the software ready ahead of hardware delivery. If the service cannot start or remain healthy while zero physical cameras are connected on the network, it cannot be validated prior to camera installation.

**Independent Test**: Can be fully tested before cameras arrive by starting the NVR service, opening the web interface from an authorized device, and confirming the dashboard loads with system status, storage indicators, and pre-configured camera slots without crashing or entering an error loop.

**Acceptance Scenarios**:

1. **Given** the NVR service is deployed with no physical cameras present on the network yet, **When** the service starts, **Then** it initializes cleanly and remains continuously healthy without crashing or restart-looping due to missing camera streams.
2. **Given** an authorized user on the local network or VPN overlay, **When** navigating to the NVR web interface, **Then** the dashboard loads and displays the two pre-staged camera slots along with live system health metrics.
3. **Given** the host server restarts, **When** the operating system completes startup, **Then** the NVR service automatically starts in the background and returns to a ready state without manual intervention.

---

### User Story 2 - Plug-and-Play Two-Camera Onboarding Upon Delivery (Priority: P1)

As a homeowner whose two ordered cameras have just been delivered and connected to the network, I want pre-structured configuration slots and secret placeholders for Camera 1 and Camera 2 (covering both live viewing/detection and recording roles), so that I only need to enter their network addresses and credentials and enable them to immediately begin live streaming, motion/object detection, and recording.

**Why this priority**: Pre-staging the two camera configurations eliminates setup friction on delivery day. The user should not have to design the configuration structure, retention rules, or credential handling from scratch when unboxing the cameras.

**Independent Test**: Can be tested before delivery using synthetic test feeds (or offline disabled camera slots) and on delivery day by populating the two camera network addresses/credentials in the isolated secrets file, enabling the cameras, and verifying that both feeds appear in the dashboard with active object detection and recording.

**Acceptance Scenarios**:

1. **Given** two pre-configured camera definitions (`camera_1` and `camera_2`) in the NVR configuration, **When** the physical cameras are still in transit, **Then** the camera slots are disabled (or bound to a safe placeholder/test source) so they do not flood system logs with connection errors or waste resources.
2. **Given** the two physical cameras have arrived and are connected to the network, **When** the operator populates their stream addresses and credentials in the local secret store and enables the two camera entries, **Then** both cameras stream live video, detect objects (such as people and vehicles), and record events without requiring any structural changes to the service deployment.
3. **Given** active camera feeds, **When** an object of interest (e.g., person or car) enters a camera's field of view, **Then** the system records the detection event, captures a snapshot/clip, and makes it browsable in the web interface.

---

### User Story 3 - Tiered Storage Separation & Automated Retention Management (Priority: P2)

As a homelab administrator, I want application configuration and event metadata stored on fast persistent storage while continuous video recordings and clips are directed to dedicated scratch storage with automatic space/retention cleanup, so that 24/7 camera writes never fill up the disk, degrade database responsiveness, or trigger parity array churn.

**Why this priority**: Video surveillance generates continuous high-volume writes. Separating metadata from bulk video footage and enforcing automatic retention pruning prevents disk exhaustion and protects the rest of the server's storage infrastructure.

**Independent Test**: Can be tested independently by inspecting the configured storage paths, writing test clip data and database entries, and verifying that database/configuration files reside on the primary application storage tier while recordings reside on the dedicated scratch storage tier outside parity monitoring.

**Acceptance Scenarios**:

1. **Given** the running NVR service, **When** configuration changes or detection event metadata are written, **Then** they are stored on the fast application storage tier.
2. **Given** active camera recording or clip generation, **When** video segments and snapshots are saved to disk, **Then** they are written exclusively to the dedicated scratch storage tier and never to parity-protected bulk storage.
3. **Given** recorded video footage accumulating over time, **When** recordings exceed the configured retention window (e.g., 7 days of continuous/motion footage and 14 days of detection events), **Then** the system automatically prunes the oldest recordings to prevent storage exhaustion.

---

### User Story 4 - Backup Protection, Secret Isolation & Health Verification (Priority: P2)

As a systems operator governed by homelab resiliency standards, I want the NVR configuration and event database backed up offsite (while excluding high-volume video recordings), camera credentials kept strictly out of version control, and automated health checks confirming service and detector readiness, so that the setup is secure, observable, and recoverable after hardware failure.

**Why this priority**: Every application on the platform must satisfy mandatory backup, secret isolation, and telemetry verification gates before completion.

**Independent Test**: Can be tested independently by running the automated verification suite to confirm health endpoint responses, verifying that zero camera passwords or stream URLs with embedded credentials exist in version control, and confirming that the NVR configuration and database are included in the encrypted offsite backup while video recordings are excluded.

**Acceptance Scenarios**:

1. **Given** the repository source tree, **When** audited for sensitive data, **Then** zero real camera passwords, stream URLs containing credentials, or private tokens exist in version control (only sanitized `.example` templates are committed).
2. **Given** the scheduled encrypted offsite backup routine, **When** a backup snapshot runs, **Then** the NVR configuration and event database are backed up safely while raw CCTV video recordings and clips on scratch storage are excluded.
3. **Given** the deployed NVR service, **When** the automated verification check runs, **Then** it confirms service health, API responsiveness, storage mount availability, and structured log output with a clean pass status.

---

### Edge Cases

- **Cameras Offline or Undelivered at Startup**: What happens when the service runs for days or weeks before the physical cameras arrive, or if a camera temporarily loses power after installation?
  *Requirement: Pre-configured cameras must default to a disabled state (or safe synthetic placeholder) prior to delivery so logs remain clean, and once enabled, if a camera goes offline, the service must continue operating for the remaining camera and automatically reconnect when the offline camera returns.*
- **Scratch Disk Space Pressure**: What happens if high activity or increased camera bitrates cause the dedicated recording scratch storage to approach full capacity earlier than the standard retention period?
  *Requirement: Retention thresholds and storage allocations must automatically expire the oldest recordings before the scratch volume reaches capacity, ensuring uninterrupted recording of new events.*
- **GPU Device Availability & Fallback**: What happens if GPU render node numbering changes across reboots or if hardware acceleration encounters an initialization issue?
  *Requirement: The system must bind GPU acceleration using stable PCI device paths (rather than volatile render node numbers) and rely exclusively on the host's existing CPU and GPU hardware for video decoding and object detection, with zero dependency on external Coral TPU peripherals.*
- **In-Memory Frame Buffer Exhaustion**: What happens when multiple high-resolution camera streams are decoded simultaneously in memory?
  *Requirement: Sufficient in-memory shared buffer space must be allocated for at least two high-resolution dual-stream (detect + record) cameras so frame processing never crashes due to shared memory exhaustion.*

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST deploy the Frigate NVR service in an isolated, self-healing runtime environment that starts automatically on host boot.
- **FR-002**: System MUST run and report healthy status immediately upon deployment even while zero physical cameras are connected on the network.
- **FR-003**: System MUST provide a pre-staged configuration containing two clearly defined camera entries (`camera_1` and `camera_2`), each pre-configured with standard dual-stream roles (`detect` for low-resolution analysis and `record` for full-resolution archiving) and default object detection targets (e.g., person, car).
- **FR-004**: Pre-staged camera entries MUST be safely disabled by default (or bound to a non-failing test source) until the physical cameras arrive, allowing the operator to activate each camera simply by entering its stream credentials/address and toggling it enabled.
- **FR-005**: System MUST decouple camera credentials, stream URLs containing usernames/passwords, and secret tokens into a gitignored local environment/secrets file, accompanied by a committed `.example` template showing the exact placeholder variables for both cameras.
- **FR-006**: System MUST store NVR configuration files and the internal event metadata database on the fast application storage tier.
- **FR-007**: System MUST store all continuous recordings, motion clips, and event snapshots on the dedicated scratch storage tier, keeping all CCTV video traffic strictly outside parity-protected storage pools.
- **FR-008**: System MUST allocate sufficient volatile in-memory frame buffer capacity to support simultaneous decoding and object detection across at least two high-resolution cameras without memory exhaustion.
- **FR-009**: System MUST enforce automated recording retention policies (defaulting to retaining general motion/continuous recordings for 7 days and tracked object detection events for 14 days) to prevent unbounded disk growth.
- **FR-010**: System MUST expose the NVR web interface and API exclusively to authorized local and VPN overlay networks, keeping unauthenticated camera streams and controls inaccessible from the public internet.
- **FR-011**: System MUST include the NVR configuration and event database in the host's encrypted offsite backup schedule while explicitly excluding bulk CCTV video recordings and clips.
- **FR-012**: System MUST direct service lifecycle logs and stream diagnostics to the standard system logging facility and provide an automated verification check confirming service readiness, API health, storage tier availability, and backup/exclusion compliance.
- **FR-013**: System MUST perform both hardware video decoding and AI object detection using the host's integrated Intel GPU (leaving the discrete AMD GPU untouched for other workloads), with no Coral TPU hardware dependencies or configuration placeholders.

### Key Entities

- **Camera Slot (`camera_1`, `camera_2`)**: Pre-structured logical camera definition containing stream inputs (sub-stream for detection, main stream for recording), enabled/disabled state, motion/object tracking preferences, and retention settings.
- **Detection Event**: Metadata record representing an identified object (e.g., person, vehicle) with timestamps, confidence score, camera reference, and links to associated thumbnail snapshots and video clips.
- **Recording Segment**: Time-bounded video file written to the scratch storage tier, governed by automatic retention expiration rules.
- **Camera Secret Profile**: Gitignored local credential set holding the RTSP/ONVIF usernames, passwords, and host/IP addresses for `camera_1` and `camera_2`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The NVR web interface and health status endpoint respond as healthy within 2 seconds of request dispatch while zero physical cameras are connected on the network.
- **SC-002**: While awaiting camera delivery, the service operates continuously with 0 unexpected restarts and 0 unhandled camera connection crash loops over a 24-hour observation window.
- **SC-003**: When the two physical cameras arrive, an operator can onboard and activate both cameras in under 5 minutes by populating only the isolated secrets file and toggling the camera enable flags, without modifying service deployment definitions or directory layouts.
- **SC-004**: 100% of video recordings, clips, and snapshots are written to the dedicated scratch storage tier, resulting in 0 bytes of CCTV footage written to parity-protected storage or transmitted to offsite cloud backups.
- **SC-005**: 100% of automated verification checks pass (confirming service health, API version/status response, storage path separation, secret isolation, and backup configuration).

## Assumptions

- **Camera Compatibility**: The two ordered cameras support standard network video streaming protocols (such as RTSP/H.264) and ideally provide both a main high-resolution stream (for recording) and a lower-resolution sub-stream (for efficient object detection).
- **Pre-Arrival State**: Until the physical cameras arrive and are assigned local IP addresses, the two camera entries in the configuration will default to `enabled: false` (with clear comments and environment variable bindings for their RTSP URLs) so the NVR UI is live and browsable immediately without logging repeated connection timeout errors.
- **Hardware Acceleration & Detector Defaults**: The system will use the host's integrated Intel UHD Graphics 770 GPU for both hardware video decoding and AI object detection (leaving the discrete AMD GPU untouched), with no Coral Edge TPU hardware assumed or configured.
- **Network Access**: Authorized users access the NVR web interface over the existing local network or Tailscale VPN overlay established in earlier platform phases; public internet exposure (such as Tailscale Funnel) is not enabled for household security cameras.
- **Host Prerequisites**: Phases 1 through 4 and the Phase 5 container runtime and encrypted offsite backup pipeline are already provisioned on the target host, providing the fast application storage path (`/opt/services`), scratch storage path (`/mnt/scratch`), and backup framework.
