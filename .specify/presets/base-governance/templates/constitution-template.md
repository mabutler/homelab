<!--
Sync Impact Report (Latest Amendment Only — Do Not Accumulate History):
- Version Change: 0.0.0 -> 1.0.0
- Modified Principles: Initial ratification from Standard Base Template.
- Modified Sections: All core sections initialized.
- Rationale: Establish baseline engineering, epistemic, and workflow guardrails.
-->

# [PROJECT_NAME] Constitution

<!--
Template Resolution Hierarchy Specification:
This template is resolved by agent skills using the native 4-tier template resolution hierarchy:
- Tier 1 (Overrides): .specify/templates/overrides/constitution-template.md
- Tier 2 (Presets): .specify/presets/<preset-id>/templates/constitution-template.md (evaluated per .specify/presets/.registry sorted ascending by priority; strategy: replace, prepend, append, wrap)
- Tier 3 (Extensions): .specify/extensions/<ext-id>/templates/constitution-template.md (evaluated per .specify/extensions/.registry sorted ascending by priority)
- Tier 4 (Core Fallback): .specify/templates/constitution-template.md

Invariant: If a requested template is not found in any of the 4 tiers, the agent MUST fail closed and emit an error per Principle II.
-->

## Sources of Truth & Authority Hierarchy

When specifications, reference documents, test harnesses, or existing code disagree, authority ranks in this strict order:

1. **[PRIMARY_SOURCE]** (e.g., Formal Protocol Specification / Regulatory Requirements)
2. **[SECONDARY_SOURCE]** (e.g., Reconciled Architecture Docs in `docs/` or Verified Simulator Behavior)
3. **[TERTIARY_SOURCE]** (e.g., Legacy Implementation / Upstream Adapter Contracts)

## Core Principles

### I. Evidence Over Invention & Bounded Investigation
Every domain behavior, protocol constant, schema element, and security requirement MUST trace to an authoritative source listed in the Authority Hierarchy above. Neither a human nor an AI agent may fill an unverified gap with a plausible guess or inference by analogy.
- **Bounded, Cited Research**: Investigation MUST traverse the Authority Hierarchy in order, consulting local reference and architecture documentation before opening primary specs or legacy source repositories. Primary source digs MUST be bounded to the specific file or section answering the question and cite `file:line` or section/page numbers. If the sources do not answer the question, the required output is **NOT FOUND** naming what was searched.
- **Centralized Open Questions**: Every unknown, ambiguity, or deferred gap that outlives a single task MUST be recorded in `reference/open-questions.md` (citing what was checked, who can resolve it, and any temporary working assumption). Undocumented gaps or silent placeholders are defects.
<!-- OPTIONAL-MODULE: MODULE-A
Action: ADD
Title: In-Code Open Question Pointers
Target: Principle I
-->
- **Pointer-Only Code Tags**: When an open question or deferred verification leaves a temporary stub or boundary gap in source code, it MAY be marked exclusively with a pointer tag (`// OPEN-QUESTION: OQ-XXX`) referencing its entry in `reference/open-questions.md`. Free-text `TODO` comments or duplicate prose explanations in source code are forbidden.
<!-- /OPTIONAL-MODULE: MODULE-A -->

### II. Two-Tier Failure Model & Fail Closed on Required State
Failures divide into two distinct categories and MUST be handled accordingly:
- **Rejected Operations (Expected / External Failures)**: Invalid inputs, unsupported requests, or transient boundary/I/O failures MUST be detected at the earliest boundary, aborted before mutating state, logged at `WARN`, and returned as an explicit, typed error result while leaving the system running. Low-level I/O and cryptographic exceptions MUST be caught narrowly at the boundary and translated into typed errors.
- **Defect Invariants (Broken Internal State)**: Programmer errors, violated preconditions, or corrupted internal state MUST NOT be caught to keep running. The affected execution scope MUST log at `CRITICAL` and halt/restart immediately so untrusted state cannot propagate.
- **Explicit Exception Disposition**: Every `catch` block MUST either (1) translate the exception into a typed boundary error, (2) enrich and rethrow, or (3) log at `WARN` and isolate/continue *only* on designated non-critical paths (e.g., best-effort cleanup or isolated dispatch loops) where failure cannot corrupt state or masquerade as a successful mutation. Truly silent swallowing requires an inline comment proving why ignoring the failure is safe.
- **Explicit Unimplemented Semantics**: Code MUST NOT substitute guessed defaults for missing required data. Unimplemented or intentionally unsupported operations on an interface surface MUST return distinct, typed `NotImplemented` or `Unsupported` results—never empty method bodies that simulate success.
- **Fail Closed on Required State**: State, checks, or configuration required for security, integrity, or diagnosability MUST be established before dependent functions run. Quietly degrading, continuing with a warning, or retrying silently in the background is forbidden unless ratified under Recorded Deviations.

### III. Behavioral, Value-Driven Testing & Deterministic Execution
Every automated test MUST guard meaningful behavioral contracts or plausible regressions through production entry points.
- **Encapsulation & Contract Focus**: Visibility MUST NOT be widened (`private` to `public`), and test-only members MUST NOT be added solely to reach internals (internal-visibility exemptions require written justification). Tests MUST verify behavioral outcomes and MUST NOT assert on log text, operator display strings, or the absence of deleted code/files.
<!-- DEFAULT-CLAUSE: PLAN-JUSTIFICATION-AND-SKIP-ALLOWLIST (REPLACEABLE-BY: MODULE-B)
Target: Principle III
-->
- **Plan Justification & Skip Allowlist**: Every `/speckit-plan` MUST list the tests it intends to write and state what risk each guards against. Comprehensive behavioral and branch coverage is expected across all domain logic, state machines, parsers, and error boundaries. Omitting unit tests without a plan justification is permitted ONLY for:
  1. Compiler-generated, schema-generated, or code-generator output.
  2. Defect-invariant guards (unreachable-code traps and internal post-validation assertions) unreachable via public entry points.
  3. Pure data carriers (DTOs, immutable value/record snapshots) and thin pass-through adapter wrappers over OS/hardware seams.
  4. Application host bootstrap entry points, declarative CLI binding declarations, and declarative UI layout markup covered by smoke/acceptance gates.
  5. One-off build/provisioning scripts verified by automated linters and live acceptance gates.
<!-- /DEFAULT-CLAUSE: PLAN-JUSTIFICATION-AND-SKIP-ALLOWLIST -->
<!-- OPTIONAL-MODULE: MODULE-B
Action: REPLACE
Target: Principle III
Replaces: PLAN-JUSTIFICATION-AND-SKIP-ALLOWLIST
Title: Strict 100% Branch Coverage Profile
-->
- **100% Branch Coverage Gate**: 100% automated branch coverage MUST be maintained across the codebase; line coverage alone does not satisfy this gate. Coverage exclusions require a written code annotation and are permitted ONLY for schema-generated code and defect-invariant checks (whose justification must name the invariant protected).
<!-- /OPTIONAL-MODULE: MODULE-B -->
- **Unprivileged, Deterministic Unit Tests**: Automated unit tests MUST run without administrator/root privileges and MUST NOT touch real disks/partitions, real network endpoints, or committed cryptographic key material (ephemeral keys/certs are generated per run). Time MUST be injected via a time abstraction or explicit timestamps and randomness seeded.
- **Hostile Boundary Coverage & Bug Ratchet**: Any parser of untrusted bytes or security verification gate MUST include negative and hostile-input tests (malformed payloads, oversized counts, offset overflows, bad signatures). Every defect discovered in integration testing, simulator runs, or production MUST receive a reproducing regression test alongside the fix.

### IV. Single Authoritative State, Enforced Boundaries & Safe Concurrency
- **Single Source of Truth**: Every piece of domain state MUST have exactly one authoritative owning model. Registries, lookup tables, and projections are read-only views or pure indexes—never competing, independently mutated copies of state owned elsewhere.
- **Structurally Enforced Boundaries**: Core domain logic MUST NOT depend on wire/serialization schema types or raw OS/hardware/process I/O. Wire translation happens strictly at the boundary and is enforced at compile time via the build/module dependency graph, not by import conventions. Disk, network, process, and hardware access MUST sit behind interface seams so unit tests use fakes.
- **Safe Concurrency & Snapshot Isolation**: A thread holding an entity state lock MUST NOT acquire another entity lock or invoke external callbacks, event subscribers, or cross-entity logic while holding the lock. Side effects are recorded inside the critical section and dispatched in order *after* the lock is released. Code outside an entity's lock works exclusively from immutable snapshots captured under the lock, never from live mutable references.
- **Disambiguated Colliding Identifiers**: When two or more identifiers or unit-bearing quantities of the same primitive type (e.g., `DeviceId` and `HostId`) are routinely passed together across method boundaries, they MUST be wrapped in distinct, non-convertible value types. Single-identifier lookups may use standard primitives.
<!-- OPTIONAL-MODULE: MODULE-C
Action: ADD
Title: Table-Driven Dispatch
Target: Principle IV
-->
- **Dispatch Is Data, Not Branches**: Behavior that varies per protocol class, command, or event code MUST be registered as data in a single startup-validated registry/table (one handler type per command), never split across hand-maintained switch statements or parallel validation/execution conditionals that can silently drift out of sync.
<!-- /OPTIONAL-MODULE: MODULE-C -->

### V. Centralized Dependencies & Protected Toolchain Gate
- **Centralized, Locked Supply Chain**: All package versions and shared compiler/linter settings MUST be declared centrally at the repository root with committed lockfiles. Project-local overrides are forbidden without documented justification. Internal shared code within the repository is consumed via project/module reference, never packaged internally.
- **Deliberate Package Selection**: Prefer mature, actively maintained libraries that substantially simplify design over custom infrastructure code; reject obscure, poorly maintained, or trivial micro-packages.
- **Human-Only Toolchain & Security Gate**: AI agents MUST NOT—without explicit human instruction—add or upgrade third-party packages, modify package sources or registries, alter SDK/toolchain versions, weaken compiler/linter warning or strictness flags, modify version manifests, or generate/modify cryptographic signing keys and certificates.
<!-- OPTIONAL-MODULE: MODULE-D
Action: ADD
Title: Regulated / Certified Systems
Target: Principle V
-->
- **Reproducible Builds & Deliberate Versioning**: Submitted components MUST build deterministically from pinned toolchains; where bit-reproducibility is impossible (e.g., OS/bootable images), component docs MUST specify the signed manifest verification used instead. major.minor versions change only by explicit human submission planning; patch is computed automatically from git history.
<!-- OPTIONAL-SUBCLAUSE: MODULE-D-AOT-TRIM
Action: OPTIONAL-INCLUSION
Parent-Module: MODULE-D
Title: AOT / Trim-Safe Shared Libraries
-->
[Optional: Shared libraries consumed by constrained environments SHOULD be AOT/trim-safe, isolating any untrimmable code to the narrowest scope with documented justification.]
<!-- /OPTIONAL-SUBCLAUSE: MODULE-D-AOT-TRIM -->
<!-- /OPTIONAL-MODULE: MODULE-D -->

### VI. Bounded Resources & Verify-Before-Destroy
- **Correctness Over Unmeasured Speed**: Absent a documented numeric performance target and benchmark in component documentation, code MUST NOT trade correctness, verification, or recoverability for speed.
- **Bounded Untrusted Input**: Every allocation size, collection count, offset, loop bound, and recursion depth derived from untrusted or external input MUST be validated against an explicit ceiling before memory allocation or iteration (using overflow-safe arithmetic). Large files and payloads MUST be streamed in fixed-size chunks rather than buffered whole in memory. Network and IPC calls MUST enforce explicit timeouts and support cancellation.
- **Verify Before Mutate/Destroy**: Destructive or irreversible steps (disk/partition erase, state reset, schema drop, file overwrite) MUST execute only after all cheap checks, space/resource checks, and full input verifications have passed, and MUST be protected by explicit confirmation or opt-in guards.

### VII. Code Hygiene, Ubiquitous Language & Safe Logging
- **Zero Warnings & Read-Only Vendored Code**: The build treats warnings as errors, and all code/scripts MUST pass configured linters. Vendored third-party code and generated schema files MUST NOT be edited or reformatted in place.
- **Ubiquitous Language**: Code identifiers, UI screens, CLI tools, and documentation share one domain vocabulary; changes MUST NOT introduce a synonym for an existing concept.
- **Present-Tense, High-Signal Comments & Docs**: Comments MUST explain the current implementation and *why* it is built that way—never narrate git or session history. Comments SHOULD document rejected alternatives only when needed to stop a developer from reintroducing a known defect via a naive refactor. Internal architectural documentation and human-facing documentation (`README.md`, quickstarts, and user guides) MUST match actual implemented behavior and be updated in the same change whenever user-visible CLI commands, agent skills, public APIs, configuration options, or end-user workflows are added, removed, or modified; purely internal changes (`INTERNAL_ONLY` refactors, non-behavioral fixes, or internal tooling) are exempt from artificial `README.md` edits.
- **Structured, Safe Logging**: Logs MUST use structured templates and strictly separate lifecycle milestones, diagnostic reasoning, recoverable boundary rejections, and fatal invariant crashes according to the severity taxonomy defined in `.specify/memory/logging-standards.md` / `docs/logging.md`. Logs and operator-visible errors MUST NEVER output secrets, private keys, credentials, raw PII, or bearer financial instruments.
<!-- OPTIONAL-MODULE: MODULE-DOCS
Action: ADD
Title: Structured Human-Facing Documentation Gate
Target: Principle VII
-->
- **Structured Human-Facing Documentation Gate**: The repository root `README.md` (and any dedicated user guide under `docs/`) MUST maintain canonical sections covering Project Overview & Architecture, Getting Started / Bootstrap Quickstart, CLI / Skill / API Usage Reference, and Configuration & Governance Verification, verified for relative link integrity and command accuracy before merge.
<!-- /OPTIONAL-MODULE: MODULE-DOCS -->

## Development Workflow & Quality Gates

- **Spec Kit Pipeline & Ephemeral Specs**: Feature work follows the Spec Kit lifecycle (`spec.md` -> `plan.md` -> `tasks.md`). A feature spec is a transient proposal for one change, not permanent documentation. Before a feature's final pull request merges, all decisions, state contracts, and known gaps that outlive the feature MUST be promoted into permanent documentation (`Architecture.md`, component docs, or `open-questions.md`), and that final pull request MUST delete the `specs/NNN-*/` folder. Production code, comments, documentation, and commit messages outside `specs/` MUST NOT cite spec folders or `FR-XXX` identifiers.
- **Pre-PR Verification**: `main` MUST always build cleanly. Before opening a pull request, the author or agent MUST run locked dependency restore, full build (zero warnings), linters, and the automated test suite locally, plus any project-defined Live/Simulator Acceptance Gate: **[ACCEPTANCE_GATE_COMMANDS]**.
- **Review & Merge Authority**: Pull requests SHOULD remain under ~500 lines; larger changes should be split. AI agents MUST NOT merge pull requests.

## Recorded Deviations

Any ratified exception to a Core Principle MUST be recorded here with: (1) Principle violated, (2) Ratifying human authority, (3) Rationale, (4) Compensating control, and (5) Known gap and documentation link.

- *None currently recorded.*

## Governance

- **Document Hierarchy**: This constitution supersedes all other repository practices. Detailed language conventions live in `.specify/memory/coding-standards.md` / `CodingStandards.md`, logging standards live in `.specify/memory/logging-standards.md` / `docs/logging.md`, as-built structural records live in `Architecture.md`, and day-to-day agent operational context lives in `CLAUDE.md` / `AGENTS.md`. Where a lower-level document conflicts with a Core Principle here, this constitution wins. Where `Architecture.md` conflicts with working, compliant code, update `Architecture.md` to match the code.
- **Precedence Order**: When principles conflict, the earlier concern wins in this exact order:
  1. Epistemic Truth, Trust Verification & Secret Safety (Principles I, VII)
  2. Fail Closed & Resource/Destructive Safety (Principles II, VI)
  3. Architectural Boundaries, Single State & Concurrency (Principle IV)
  4. Testing & Supply-Chain/Toolchain Gates (Principles III, V)
  5. Code Hygiene & Style (Principle VII)
  6. Unbenchmarked Performance (Principle VI)
  Degrading a higher-ranked concern to serve a lower-ranked one requires human owner ratification and an entry under **Recorded Deviations**.
- **Amendment & Versioning**: Amendments require explicit human approval, a rationale, and a Semantic Version bump (`MAJOR` for backward-incompatible principle removals/redefinitions; `MINOR` for new principles or expanded gates; `PATCH` for clarifications). Only the most recent amendment summary is kept in the top HTML sync comment.

**Version**: [CONSTITUTION_VERSION] | **Ratified**: [RATIFICATION_DATE] | **Last Amended**: [LAST_AMENDED_DATE]
