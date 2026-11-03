# Feature Specification: Target Host Antigravity Installation & Remote Control

**Feature Branch**: `007-antigravity-remote-control`

**Created**: 2026-11-02

**Status**: Draft

**Input**: User description: "In a new worktree, I want to install antigravity onto the target machine. The intention is to have it available with remote control so I can send instructions to change things while out and about. Initially I will use this to build out the rest of the host project"

## Clarifications

### Session 2026-11-02

- Q: Target machine connection details and live deployment gate → A: Target host is `admin@192.168.4.57`; automation must be prepared in the worktree first and MUST NOT be executed against `admin@192.168.4.57` until the user explicitly confirms the target machine is ready.
- Q: What default command-execution permission policy should the Antigravity agent use on `admin@192.168.4.57` when you send instructions via Remote Control? → A: Autonomous (`always-proceed` / `dangerously-skip-permissions`), auto-approving workspace edits and terminal commands so unattended remote build-out tasks execute hands-free (relying on encrypted offsite backups for recovery).
- Q: How should initial Antigravity authentication and Remote Control registration be completed on `admin@192.168.4.57` during first-time setup? → A: Option A (Seed if available from backup or controller auth profile; otherwise fall back to printing a one-time browser OAuth URL during setup).
- Q: How should the `homelab2` repository checkout on `admin@192.168.4.57` authenticate with GitHub (`origin`) so the remote agent can pull and push worktree branches while you are out and about? → A: Option A (Configure persistent Git push/pull authentication for `admin` on `192.168.4.57` via dedicated SSH key or `gh` auth token stored in the gitignored/backed-up host credential store).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Persistent Remote-Controlled Agent on Target Host (Priority: P1)

As a homelab operator away from my primary workstation, I want Antigravity installed on the target machine with its Remote Control capability running persistently in the background, so that I can connect from a mobile device or external browser while out and about and send instructions to inspect, modify, and build out the host project.

**Why this priority**: This is the core capability requested by the user. Without a persistent, reachable Remote Control session on the target machine, the operator cannot issue instructions remotely when away from their desk.

**Independent Test**: Can be fully tested by provisioning the target machine, verifying that the Antigravity CLI and Remote Control background daemon are installed and active, rebooting or logging out of the host, and confirming that the target machine remains online and responsive to a remote instruction sent from the centralized Remote Control web/mobile interface.

**Acceptance Scenarios**:

1. **Given** a provisioned target machine with network connectivity, **When** the Antigravity installation and configuration automation completes, **Then** the Antigravity binary is available to the operator account and the Remote Control daemon is registered to run persistently across user logouts and host reboots.
2. **Given** the Remote Control daemon is authenticated and active on the target machine, **When** the operator sends an instruction from a remote device (e.g., mobile browser) while away from home, **Then** the agent on the target machine receives the prompt, executes the requested task within the host workspace, and streams results back to the remote interface.
3. **Given** the target machine undergoes a scheduled or unexpected reboot, **When** the operating system finishes booting without an interactive user login, **Then** the Remote Control service starts automatically within 60 seconds and re-establishes its remote connection.
4. **Given** a transient internet or upstream network disconnection, **When** network connectivity is restored, **Then** the Remote Control service automatically reconnects without requiring manual intervention on the host.

---

### User Story 2 - Host Project Workspace Readiness for Autonomous Build-Out (Priority: P1)

As a homelab developer using Remote Control on the target machine, I want the host project repository checked out on the target machine with full support for isolated worktrees and local host execution, so that I can instruct the remote agent to build out remaining phases of the host project directly on the server.

**Why this priority**: The primary initial use case for Remote Control on the target machine is building out the rest of the host project (`homelab2`). The agent needs an initialized project workspace, version control identity, and appropriate local execution privileges on the target machine to develop, test, and apply changes safely.

**Independent Test**: Can be fully tested by initiating a remote session targeting the host project directory on the target machine, instructing the agent to create a feature worktree, run project verification checks, and apply a configuration update to the host.

**Acceptance Scenarios**:

1. **Given** the target machine has Antigravity installed, **When** the operator opens a Remote Control session to work on the host project, **Then** a clean, up-to-date working copy of the host project repository is present in a standard operator workspace path on the target machine.
2. **Given** an active remote instruction to develop a new capability, **When** the agent creates or switches to an isolated worktree on the target machine, **Then** all project specifications, templates, and automation scripts are accessible and executable locally on the target machine.
3. **Given** an instruction that requires applying or verifying system state on the target machine, **When** the agent runs project automation or verification routines, **Then** the operator environment has the required permissions and dependencies to execute idempotent changes and validate system health without blocking on unanswerable local terminal prompts.

---

### User Story 3 - Credential Isolation, Backup Coverage & Health Verification (Priority: P2)

As a systems administrator maintaining a resilient server, I want Antigravity's authentication state, configuration profile, and service health to be continuously verified and included in encrypted offsite backups (while keeping all tokens and secrets out of git), so that the remote control capability adheres to platform governance and survives disaster recovery.

**Why this priority**: In accordance with platform governance (Principles III, IV, and V), every persistent service on the host must verify its health and telemetry, never leak credentials into version control, and protect its stateful authentication/configuration files in encrypted offsite backups.

**Independent Test**: Can be tested independently by running the automated verification suite to confirm daemon health and log output, verifying that zero authentication tokens exist in git status/history, and confirming that the agent's configuration and auth state paths are registered in the offsite backup inventory.

**Acceptance Scenarios**:

1. **Given** the Antigravity service is deployed on the target machine, **When** the phase health verification suite executes, **Then** it asserts binary availability, persistent service status, active Remote Control connection state, and structured log output with a zero exit code.
2. **Given** active authentication tokens and session state in the operator's Antigravity profile on the target host, **When** inspecting the project git repository, **Then** zero credentials, session tokens, or machine-specific keys are tracked in version control.
3. **Given** an scheduled or on-demand encrypted offsite backup run, **When** the backup snapshot completes, **Then** the operator's Antigravity configuration and authentication state on the target host are included in the encrypted backup set for disaster recovery restoration.

---

### Edge Cases

- **Initial Unauthenticated State**: When Antigravity is installed on a fresh target machine for the first time before user authentication has occurred (and no backup state has been restored), how does automation behave? The installation and workspace provisioning must succeed idempotently, and the verification/setup flow must clearly surface the one-time authorization link or restore path without failing destructively.
- **Concurrent Worktrees & File Locking**: What happens when the remote agent is instructed to work on a new feature while another branch or worktree has uncommitted modifications on the target machine? The workspace layout must support creating isolated worktrees cleanly without corrupting active work.
- **Unattended Permission Prompts**: What happens if the operator sends a remote instruction while out and about and the agent requires tool execution permissions? The agent configuration on the target host is configured for autonomous execution (`always-proceed` / skip-permissions mode) so multi-step tasks never hang waiting on an unmonitored local console or constant mobile approval prompts.
- **Network Outage or Upstream Service Interruption**: If the target machine boots during a WAN outage, the persistent service must retry gracefully with backoff and log structured diagnostic events rather than entering a permanently failed state.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide idempotent automation to install the Antigravity CLI on the target machine (`admin@192.168.4.57`) under the designated non-root operator account (`admin`).
- **FR-002**: System MUST configure the Antigravity Remote Control background service to run persistently at boot (independent of active interactive SSH login sessions) with a recognizable machine instance name.
- **FR-003**: System MUST ensure the Remote Control service automatically restarts on failure and reconnects after network interruptions.
- **FR-004**: System MUST provision and maintain a working checkout of the host project repository (`homelab`) in the `admin` operator's workspace on `admin@192.168.4.57`, configured with persistent Git push/pull authentication (SSH key or `gh` auth token excluded from Git and backed up via Restic), isolated worktree support, and local self-provisioning capabilities.
- **FR-005**: System MUST configure default workspace and tool execution settings for the target machine in autonomous mode (`always-proceed` / skip-permissions) so instructions sent via Remote Control execute hands-free without blocking on permission prompts.
- **FR-006**: System MUST support automated seeding of Antigravity authentication and configuration state from encrypted offsite backups or the controller workstation profile when available, and automatically fall back to displaying a one-time browser authorization URL during setup when no prior auth state exists.
- **FR-007**: System MUST register the target machine's Antigravity configuration and authentication state directory in the host's encrypted offsite backup pipeline while excluding transient cache and temporary runtime files.
- **FR-008**: System MUST strictly exclude all Antigravity authentication tokens, session credentials, and private keys from version control.
- **FR-009**: System MUST direct all Remote Control service lifecycle events and errors to standard system logs for centralized triage.
- **FR-010**: System MUST provide an automated verification script that validates installation integrity, persistent service status, workspace readiness, backup inclusion, and Remote Control registration status.
- **FR-011**: Automation workflows and agents MUST NOT execute live provisioning or verification against `admin@192.168.4.57` until the operator explicitly confirms the target machine is ready.

### Key Entities

- **Remote Control Instance**: Represents the persistent Antigravity daemon running on the target host, identified by its registered instance name, service lifecycle state, and association with the operator's account.
- **Target Host Workspace**: Represents the operator's project directory and associated worktrees on the target machine where the remote agent reads specifications, edits files, and executes host automation.
- **Agent Profile & Auth State**: Represents the local configuration settings, permission grants, and authentication credentials stored in the operator's profile directory on the target host (gitignored and backed up offsite).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After initial setup or host reboot, the target machine appears online and ready for instructions in the operator's Remote Control interface within 60 seconds of network availability, with zero manual terminal commands required post-reboot.
- **SC-002**: From an external device (mobile or remote browser), the operator can initiate a task in the target host workspace, create an isolated worktree, and complete a host configuration change end-to-end in under 5 minutes.
- **SC-003**: Re-running the installation and configuration automation against an already-configured target machine completes in under 60 seconds with zero unintended state changes and zero interruption to an active Remote Control session.
- **SC-004**: 100% of automated health verification checks pass (`0` exit code), confirming binary availability, persistent service readiness, log collection, workspace availability, and zero secrets in version control.
- **SC-005**: Following a simulated state reset on the target machine, restoring the agent profile from the encrypted offsite backup recovers Remote Control configuration and authentication state in under 2 minutes without requiring re-configuration of workspace settings.

## Assumptions

- The target machine has already completed Phases 1 through 4 of the project roadmap (base OS installation, non-root operator user with administrative privileges, outbound internet connectivity, and local storage mounts).
- The operator possesses an active Google account authorized to use Antigravity and can complete a one-time browser-based authorization step during initial first-time registration (subsequent runs and disaster recovery restores reuse the backed-up authentication state).
- Outbound HTTPS/WSS connectivity from the target machine to Google Antigravity cloud endpoints is permitted by the host firewall (no inbound public port forwarding is required on the home router).
- The primary workstation and the target machine can synchronize project changes via the shared Git remote repository (`origin`), allowing work done via Remote Control on the target machine to be pushed and pulled cleanly across worktrees.
