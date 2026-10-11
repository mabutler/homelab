# homelab2 Constitution

## Core Principles

### I. Pragmatic Declarative-First Automation
Infrastructure MUST be declared using configuration management and Infrastructure-as-Code
(e.g., Ansible, OpenTofu) as the primary automation interface. When declarative tooling
encounters friction, poor ecosystem support, or disproportionate complexity (e.g., storage pooling
such as mergerfs, hardware-specific partitioning), automation MUST cleanly fall back to modular,
self-contained, idempotent shell scripts. Script fallbacks MUST maintain explicit contracts,
document inputs/outputs, and live in designated script modules rather than inline workarounds.

*Rationale: Declarative IaC ensures reproducibility and maintainability, but dogmatic purity
creates brittle edge cases. Pragmatic scripting fallbacks keep the stack robust and easy to operate.*

### II. Strict Idempotency & Safe Convergence
All automation routines, playbooks, tasks, and scripts MUST be safely re-runnable without
unintended state divergence, duplicate resources, or service disruption. Executing automation
against an already converged target MUST produce a clean, no-op exit. Destructive operations
(such as formatting drives, partition recreation, or secret destruction) MUST be protected by
explicit opt-in verification guards and MUST NEVER execute silently or by default.

*Rationale: Infrastructure automation must inspire confidence; safe, repeatable convergence
is required to support hands-off runs and automated maintenance.*

### III. Automated Verification & Acceptance Gates
No service, configuration, or infrastructure component is complete without automated verification.
Every deployment MUST define explicit health assertions, smoke tests, or status checks (e.g.,
systemd unit active status, HTTP endpoint response, socket connectivity, mount accessibility).
Automated tasks MUST verify that target states are live and functional before declaring completion,
failing fast with actionable error messages on stderr.

*Rationale: Silent failures and partial provisioning corrupt homelab reliability. Automated
acceptance tests confirm end-to-end functionality immediately upon convergence.*

### IV. Zero Cleartext Secrets & Isolated Configuration
Sensitive parameters—including passwords, tokens, private keys, API credentials, and encryption
keys—MUST NEVER be committed to version control in plaintext. Secrets MUST be encrypted at rest
(using SOPS with age, Ansible Vault, or equivalent) or retrieved dynamically at runtime from an
isolated secret store. Configuration templates MUST decouple secrets from environment definitions.
Accidentally exposed cleartext credentials trigger immediate revocation, rotation, and git history
cleanup.

*Rationale: Public or private repositories must remain secure by default against credential leakage
and lateral access.*

### V. Disaster Recovery & Backup by Design
Every stateful service, configuration directory, and persistent dataset MUST define an automated
backup schedule and a verified restoration procedure. Backup artifacts MUST be tested periodically
for integrity. An untested backup MUST be considered non-existent. Disaster recovery procedures
MUST allow recreating services on clean hardware or VMs using only the version-controlled repository
and off-host backup stores.

*Rationale: Hardware failures and configuration corruption are inevitable over time; verified
recovery ensures low stress and zero data loss.*

### VI. Modular & Decoupled Architecture
System components, roles, and applications MUST remain modular, loosely coupled, and independently
operable. Monolithic configurations and hidden inter-service dependencies MUST be avoided. Services
MUST communicate over standardized protocols (e.g., TCP/IP, Unix sockets, REST) with clear network
and storage boundaries. Individual services MUST be deployable, restartable, or decommissionable
without impacting unrelated workloads.

*Rationale: Modular components reduce blast radius, simplify debugging, and permit incremental
evolution of individual homelab capabilities.*

### VII. Stability-First & Annual Maintenance Cadence
The platform prioritizes rock-solid stability, low operational toil, and minimal cognitive overhead
over chasing bleeding-edge upstream releases. Deployments MUST default to stable/LTS releases,
pinned versions, and battle-tested defaults. Day-to-day operations MUST require zero intervention.
Major platform updates, kernel upgrades, and breaking architectural migrations MUST be planned on an
annual maintenance cadence with rehearsed rollback plans.

*Rationale: A homelab should serve the household quietly and reliably, not demand constant weekly
tinkering or fragile maintenance chores.*

## Operational & Security Standards

- **Minimalist Footprint**: Unnecessary background daemons, complex container runtimes where
  plain services suffice, and speculative abstractions are prohibited (YAGNI). Keep system footprint
  lean and understandable.
- **Structured Logging & Diagnostics**: Services and scripts MUST direct logs to standard sinks
  (journald/stdout/stderr). Log outputs MUST provide sufficient context to triage failures without
  attaching interactive debuggers.
- **Network Isolation & Least Privilege**: Services MUST expose ports only to designated network
  segments or overlay networks (e.g., Tailscale/VLANs). Non-root execution is required for all
  application workloads.

## Workflow & Quality Gates

- **Spec Kit Lifecycle**: New infrastructure features, topology changes, and services MUST follow
  the Spec Kit workflow (`spec.md` -> `plan.md` -> `tasks.md`) to guarantee constitutional compliance
  before execution.
- **Linting & Pre-flight Validation**: All scripts and configuration files MUST pass automated
  linting (e.g., `ansible-lint`, `shellcheck`, syntax validation) before merging or running in
  production.
- **Version Control & Documentation**: Every change MUST be committed with a descriptive git
  commit message. Operational procedures and recovery steps MUST be documented alongside code.

## Governance

This Constitution acts as the supreme architectural standard for the `homelab2` repository.
All specifications, designs, implementation tasks, and operational playbooks MUST comply with the
Core Principles and Operational Standards defined herein.

- **Amendment Process**: Any modification to this constitution requires a documented proposal,
  an explanation of the underlying need, an evaluation of impact on existing infrastructure, and a
  formal version bump.
- **Versioning Policy**: Semantic versioning (MAJOR.MINOR.PATCH) is strictly applied:
  - MAJOR: Incompatible governance changes, fundamental architectural shifts, or principle removals.
  - MINOR: Addition of new principles, structural sections, or materially expanded operational gates.
  - PATCH: Wording refinements, clarifications, and non-semantic corrections.
- **Compliance Enforcement**: All Spec Kit artifacts (`spec.md`, `plan.md`, `tasks.md`) and code
  reviews MUST explicitly reference and verify adherence to these principles prior to implementation.

**Version**: 1.0.0 | **Ratified**: 2026-10-11 | **Last Amended**: 2026-10-11
