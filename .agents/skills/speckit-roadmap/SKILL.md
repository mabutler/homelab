---
name: "speckit-roadmap"
description: "Author, visualize, mutate, audit, synchronize, and hand off project-level strategic roadmaps with Spec Kit feature specifications."
compatibility: "Requires spec-kit project structure with .specify/ directory"
metadata:
  author: "github-spec-kit"
  source: "templates/commands/roadmap.md"
---


## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Check for extension hooks (before roadmap execution)**:
- Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under the `hooks.before_roadmap` key.
- If the YAML cannot be parsed or is invalid, do not skip silently: tell the user that `.specify/extensions.yml` could not be read (include the parser error) and that no hooks were checked, including any mandatory (`optional: false`) hooks registered there, then continue normally.
- Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
- For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
  - If the hook has no `condition` field, or it is null/empty, treat the hook as executable.
  - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation.
- When constructing command invocations from hook command names, replace dots (`.`) with hyphens (`-`). For example, `speckit.git.commit` → `/speckit-git-commit`.
- For each executable hook, output the following based on its `optional` flag:
  - **Optional hook** (`optional: true`):
    ```
    ## Extension Hooks

    **Optional Pre-Hook**: {extension}
    Command: `/{command}`
    Description: {description}

    Prompt: {prompt}
    To execute: `/{command}`
    ```
  - **Mandatory hook** (`optional: false`):
    ```
    ## Extension Hooks

    **Automatic Pre-Hook**: {extension}
    Executing: `/{command}`
    EXECUTE_COMMAND: {command}
    ```
    After emitting the block above you MUST actually invoke the hook and wait for it to finish before continuing. Run it the same way you would run the command yourself in this agent/session. Emitting the block alone does not run the hook.
- If no hooks are registered or `.specify/extensions.yml` does not exist, skip silently.

---

## Outline

You manage the strategic project roadmap in `ROADMAP.md` at the repository root. `ROADMAP.md` is **Protected Project-Owned User State** and bridges multi-phase vision with tactical feature specifications (`specs/NNN-*/`).

### 1. Template Resolution (Native 4-Tier Hierarchy)

When authoring, scaffolding, migrating, or validating `ROADMAP.md`, resolve `roadmap-template.md` natively using the 4-tier hierarchy:
1. **Tier 1 (Overrides)**: `.specify/templates/overrides/roadmap-template.md` (strategy: `replace`)
2. **Tier 2 (Presets)**: `.specify/presets/<preset-id>/templates/roadmap-template.md` (evaluated per `.specify/presets/.registry` in ascending priority order, respecting composition strategies from `preset.yml`)
3. **Tier 3 (Extensions)**: `.specify/extensions/<ext-id>/templates/roadmap-template.md` (evaluated per `.specify/extensions/.registry` in ascending priority order)
4. **Tier 4 (Core Fallback)**: `.specify/templates/roadmap-template.md`

**Fail-Closed Invariant**:
If `roadmap-template.md` is not found in any of the 4 tiers, you **MUST** fail closed, emit a `CRITICAL` diagnostic per Constitutional Principle II:
```text
[CRITICAL] Broken Internal Invariant: roadmap-template.md could not be resolved across any of the 4 template tiers (overrides, presets, extensions, core fallback). Halting execution.
```
and halt immediately without modifying any files.

When resolved successfully, log:
```text
[INFO] Roadmap template resolved from {ResolvedTierPath} for {OperationMode}
```

---

### 2. Operation Mode Dispatch

Parse `$ARGUMENTS` to determine the execution mode:

| Invocations & Arguments | Mode | Description |
|---|---|---|
| `/speckit-roadmap` (no args or general prompt) | **Mode 1: Scaffold / Authoring** | Scaffold new `ROADMAP.md` or migrate existing unstructured `ROADMAP.md` to canonical schema. |
| `/speckit-roadmap --add "..." [--after <id>] [--prerequisites "..."]`<br>`/speckit-roadmap --update <id> "..."`<br>`/speckit-roadmap --defer <id> [--reason "..."]` | **Mode 2: Phase Mutation** | Add, update, or defer phases in `ROADMAP.md`. |
| `/speckit-roadmap --status`<br>`/speckit-roadmap --check` | **Mode 3: Status & Drift Audit** | **Read-Only**: Static linting (`RM-LINT-001`..`006`) and status drift detection against repository artifacts. |
| `/speckit-roadmap --sync` | **Mode 4: Status Synchronization** | Update `Status` and `Spec` in `ROADMAP.md` to match verified repository evidence (`InferredEvidenceStatus`). |
| `/speckit-roadmap --next [--worktree] [--force]`<br>`/speckit-roadmap --specify <id> [--worktree] [--force]` | **Mode 5: Specify Handoff** | Select eligible phase, verify prerequisites, transition to `IN_PROGRESS`, and hand off to `/speckit-specify`. |

---

### 3. Mode 1: Scaffold & Interactive Authoring

**Purpose**: Initialize a new `ROADMAP.md` or upgrade an existing legacy `ROADMAP.md` to conform to the canonical 7-column schema.

1. **Check Existing `ROADMAP.md`**:
   - If `ROADMAP.md` does not exist:
     - Scaffold a new `ROADMAP.md` using the resolved `roadmap-template.md`.
     - Set document H1 to `# [PROJECT NAME] Roadmap` (infer project name from workspace folder, `package.json`, or user prompt).
     - Set `**Last Updated**: YYYY-MM-DD` to the current date.
     - Populate phases based on user instructions in `$ARGUMENTS` or provide conforming initial phase placeholders.
   - If `ROADMAP.md` exists but does not conform to the 7-column canonical schema:
     - **Preserve All Existing Prose**: Never discard existing problem statements, architectural notes, design decisions, or phase descriptions.
     - Migrate the `## Overview of Initiatives` table to all 7 canonical columns:
       `| Phase | Initiative | Status | Prerequisites | Spec | Goal | Key Deliverables |`
     - For each phase, ensure sequential `## Phase N: [Initiative Title]` detailed sections exist with all required subsections:
       - `### Metadata` (`Status`, `Prerequisites`, `Spec Directory`)
       - `### Problem Statement`
       - `### Architectural Fit in Spec Kit` (or `### Architectural Fit & Scope`)
       - `### Key Deliverables`
       - `### Key Design Decisions to Resolve During Spec`
     - Update `**Last Updated**: YYYY-MM-DD` and governance line.

2. **Entity Invariants Enforcement**:
   - `overview_table.length == phases.length` and `phases.length >= 1`.
   - 1-to-1 sequential matching between Overview rows and detailed sections.

---

### 4. Mode 2: Phase Mutation (`--add`, `--update`, `--defer`)

**Purpose**: Safely modify phase definitions and dependencies without corrupting roadmap structure.

1. **Validation Constraints**:
   - Every `phase_id` MUST match `^Phase [1-9][0-9]*$` (e.g., `Phase 1`, `Phase 7`).
   - Every `declared_status` MUST be a valid member of `{PLANNED, IN_PROGRESS, COMPLETED, DEFERRED}`.
   - **Prerequisite Integrity**:
     - When prerequisites are specified (not `None`), every entry MUST reference an existing valid `phase_id`.
     - Every prerequisite phase MUST have a strictly earlier phase number (`phase_number < current.phase_number`).
     - Self-references (`Phase N` depending on `Phase N`) and cyclic dependencies are strictly prohibited.
     - If an invalid prerequisite is detected, fail closed, log `[WARN] Invalid prerequisite reference: {reason}`, and halt without modifying `ROADMAP.md`.

2. **Operations**:
   - `--add "<description>" [--after <phase-id>] [--prerequisites "<list>"]`:
     - Calculate the new phase number `N`. If `--after Phase M` is specified, insert after `Phase M` and renumber subsequent phases consistently, or append as the next sequential phase number.
     - Insert a new row in `## Overview of Initiatives` with `Status = PLANNED`, `Spec = —`.
     - Append the corresponding `## Phase N: <Title>` section with all 5 required subsections.
   - `--update <phase-id> "<changes>"`:
     - Locate `phase_id` in Overview table and detailed sections.
     - Apply requested updates to title, goal, deliverables, problem statement, or decisions while maintaining schema conformance.
   - `--defer <phase-id> [--reason "<rationale>"]`:
     - Update status to `DEFERRED` in both Overview table and `### Metadata`.
     - Record deferral rationale under `### Problem Statement` or `### Metadata`.

3. **Update Date**:
   - Always refresh `**Last Updated**: YYYY-MM-DD` upon mutation.

---

### 5. Mode 3: Status & Drift Audit (`--status` and `--check`)

**Purpose**: Execute static schema linting and reconcile declared roadmap status against actual repository evidence. **This mode is strictly read-only and never modifies files on disk.**

1. **Structural Linting Gates (`RM-LINT-001` through `RM-LINT-006`)**:
   Evaluate `ROADMAP.md` against these 6 declarative gates:
   - `RM-LINT-001`: `ROADMAP.md` exists at repository root and is non-empty. If missing/empty, log `[WARN] ROADMAP.md is missing or empty` and report failure.
   - `RM-LINT-002`: `## Overview of Initiatives` table header contains all 7 canonical columns:
     `| Phase | Initiative | Status | Prerequisites | Spec | Goal | Key Deliverables |`
   - `RM-LINT-003`: Exactly 1-to-1 sequential correspondence between `**Phase N**` rows in the Overview table and `## Phase N: <Title>` detailed sections, with no duplicate or missing phase numbers.
   - `RM-LINT-004`: Every `Status` token in Overview table and `### Metadata` is a valid member of `{PLANNED, IN_PROGRESS, COMPLETED, DEFERRED}` and matches between Overview and Metadata.
   - `RM-LINT-005`: Every phase listed in `Prerequisites` (other than `None`) references an earlier defined phase (`Phase M` where `M < N`) with no self-dependencies or cycles.
   - `RM-LINT-006`: Every `## Phase N` section contains all 5 required subsections:
     `### Metadata`, `### Problem Statement`, `### Architectural Fit in Spec Kit` (or secondary alias `### Architectural Fit & Scope`), `### Key Deliverables`, and `### Key Design Decisions to Resolve During Spec`.

2. **Deterministic Evidence Inference Engine (`InferredEvidenceStatus`)**:
   For each phase `Phase N`:
   - **Discover Linked Spec Directory (`resolved_spec_dir`)**:
     - Check explicit `Spec` column / `### Metadata` (e.g., `specs/NNN-<short-name>/`) in current checkout and active worktrees (via `git worktree list`).
     - Scan `specs/` (in current checkout and active worktrees) for candidate directories matching `00N-*` or `0N-*` and initiative title slug.
     - If multiple directories match ambiguously without an explicit link, flag `AMBIGUOUS_MATCH`.
   - **Compute `InferredEvidenceStatus`**:
     - `DEFERRED`: If `declared_status == DEFERRED` in `ROADMAP.md`, preserve `DEFERRED` (human override).
     - `COMPLETED`:
       - `resolved_spec_dir` exists AND contains `spec.md`, `plan.md`, and `tasks.md` where total tasks (`- [x]` + `- [ ]`) > 0 and unchecked tasks (`- [ ]`) == 0; **OR**
       - Git commit history (`git log --oneline`) records a verified completion commit for `00N-<slug>` / `Phase N`.
     - `IN_PROGRESS`:
       - `resolved_spec_dir` exists (in primary checkout or an active git worktree) with `spec.md` present, and `tasks.md` is either absent or contains >= 1 unchecked `- [ ]` task; **OR**
       - An active git branch or worktree matching `00N-*` exists with open development.
     - `PLANNED`:
       - None of the above conditions hold (no spec directory, active worktree, or completion commit).

3. **Reconciliation State Classification**:
   - `SYNCED`: `declared_status == inferred_evidence_status`, `declared_spec_dir == resolved_spec_dir`, and all structural gates pass.
   - `STATUS_DRIFT`: `declared_status != inferred_evidence_status` or `declared_spec_dir != resolved_spec_dir`.
   - `AMBIGUOUS_MATCH`: Multiple candidate spec directories match without an explicit link.
   - `STRUCTURAL_ERROR`: Any `RM-LINT-*` gate fails.

4. **Output Report Format**:
   Emit structured Markdown report conforming to `.specify/memory/logging-standards.md`:
   ```markdown
   ### Spec Kit Roadmap Status Report

   **Roadmap File**: `ROADMAP.md`  
   **Mode**: Status Audit (Read-Only)  
   **Template Tier**: Tier 2 (.specify/presets/base-governance/templates/roadmap-template.md)  

   #### Phase Reconciliation Summary

   | Phase | Initiative | Declared Status | Inferred Evidence | Spec Directory | Prerequisites | Alignment |
   | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
   | **Phase N** | ... | `...` | `...` | `...` | ... | `SYNCED` / `STATUS_DRIFT` |

   #### Structural Lint & Diagnostics
   - **Structural Gates (`RM-LINT-001`..`006`)**: `PASS` (6/6 gates passed)
   - **Next Eligible Phase for `/speckit-roadmap --next`**: Phase N (...)
   ```
   Log telemetry milestone:
   ```text
   [INFO] Roadmap status audit completed across {PhaseCount} phases ({SyncedCount} SYNCED, {DriftCount} STATUS_DRIFT)
   ```

---

### 6. Mode 4: Status Synchronization (`--sync`)

**Purpose**: Reconcile and synchronize status markers in `ROADMAP.md` to match verified repository evidence.

1. **Run Status Audit (Mode 3)**:
   - Compute `InferredEvidenceStatus` and `resolved_spec_dir` for all phases.
   - If structural errors (`STRUCTURAL_ERROR`) exist, log `[WARN] Cannot sync ROADMAP.md due to structural lint errors` and halt.

2. **Apply Updates**:
   - For every phase with `STATUS_DRIFT`:
     - Update the `Status` column in `## Overview of Initiatives` to `` `<InferredEvidenceStatus>` ``.
     - Update the `Spec` column in `## Overview of Initiatives` to `` `<resolved_spec_dir>` `` (or `—` if none).
     - Update `**Status**:` in the phase's `### Metadata` section.
     - Update `**Spec Directory**:` in the phase's `### Metadata` section.
   - Update `**Last Updated**: YYYY-MM-DD` to the current date.
   - **Preserve All Other Content**: Keep all problem statements, architectural notes, deliverables, and design decisions intact.

3. **Log Telemetry**:
   ```text
   [INFO] Roadmap synchronized: updated {UpdatedCount} phase(s) in ROADMAP.md
   ```

---

### 7. Mode 5: Specify Handoff (`--next` and `--specify <phase-id>`)

**Purpose**: Smoothly transition from a roadmap initiative to a detailed feature specification (`/speckit-specify`), with prerequisite enforcement and optional git worktree isolation.

1. **Select Target Phase**:
   - If `--specify <phase-id>` is provided: select that specific phase.
   - If `--next` is provided: select the earliest `PLANNED` phase whose declared `Prerequisites` are all `COMPLETED` (and not `DEFERRED`).

2. **Prerequisite Check & Boundary Guard**:
   - Verify that all phases listed in `Prerequisites` for the selected phase have status `COMPLETED`.
   - If any prerequisite is NOT `COMPLETED`:
     - Unless `--force` is specified, **FAIL CLOSED**:
       ```text
       [WARN] Boundary rejection: Cannot hand off {PhaseId} ({InitiativeTitle}) to /speckit-specify because prerequisite {PrereqId} is incomplete (status: {Status}). Pass --force to override.
       ```
     - Halt immediately before modifying `ROADMAP.md` or creating spec directories.

3. **Compute Feature Slug**:
   - Derive 3-digit prefix `<NNN>` from phase number (e.g., `Phase 6` → `006`).
   - Derive `<short-name>` from Initiative Title (e.g., `Human-Facing Documentation Standards & Governance` → `006-human-docs-governance`).
   - Feature directory: `specs/<NNN>-<short-name>/`.

4. **Update `ROADMAP.md`**:
   - Update the phase's `Status` to `IN_PROGRESS`.
   - Update the phase's `Spec` to `` `specs/<NNN>-<short-name>/` `` in both Overview table and `### Metadata`.
   - Update `**Last Updated**: YYYY-MM-DD`.

5. **Worktree Isolation (if `--worktree` requested)**:
   - Add `.worktrees/` to primary `.git/info/exclude` if not already present.
   - Create worktree: `git worktree add -b <NNN>-<short-name> .worktrees/<NNN>-<short-name> HEAD`.
   - Set isolated feature state: write `{"feature_directory": "specs/<NNN>-<short-name>"}` to `.worktrees/<NNN>-<short-name>/.specify/feature.json`.

6. **Extract Structured Phase Context & Invoke `/speckit-specify`**:
   - Extract:
     - `Initiative Title`
     - `Goal`
     - `### Problem Statement`
     - `### Architectural Fit in Spec Kit`
     - `### Key Deliverables`
     - `### Key Design Decisions to Resolve During Spec`
   - Log milestone:
     ```text
     [INFO] Selected {PhaseId} ({InitiativeTitle}) for /speckit-specify handoff targeting {SpecDir}
     ```
   - Invoke `/speckit-specify` with the extracted context.

---

### 8. Telemetry & Governance Standards Adherence

In strict compliance with `.specify/memory/constitution.md`, `.specify/memory/coding-standards.md`, and `.specify/memory/logging-standards.md`:
- **100% Script-Free**: This skill contains ZERO calls or references to shell automation scripts. All logic runs natively through agent file inspection and git CLI commands.
- **Principle III (Zero Automated Tests)**: Verification is purely static (`--check`, `--status`, schema validation). No test files or suites are created.
- **Structured Log Levels**:
  - `INFO`: Milestones (template resolved, status audit complete, roadmap synchronized, specify handoff).
  - `WARN`: Recoverable boundary rejections, unfulfilled prerequisites, schema lint failures, status drift.
  - `CRITICAL`: Fatal broken internal invariants (missing template across all 4 tiers).
- **Safe Logging**: Never output secrets, tokens, or raw credentials.

---

## Mandatory Post-Execution Hooks

**You MUST complete this section before reporting completion to the user.**

Check if `.specify/extensions.yml` exists in the project root.
- If it does not exist, or no hooks are registered under `hooks.after_roadmap`, skip to the Completion Report.
- If it exists, read it and look for entries under the `hooks.after_roadmap` key.
- If the YAML cannot be parsed or is invalid, do not skip silently: tell the user that `.specify/extensions.yml` could not be read (include the parser error) and continue to the Completion Report.
- Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
- For each remaining hook without a non-empty `condition`:
  - Optional hook (`optional: true`): output command and prompt.
  - Mandatory hook (`optional: false`): emit `EXECUTE_COMMAND:` and invoke the hook.

---

## Completion Report

Report final status with a clear summary:
- Operational mode executed.
- Roadmap file path (`ROADMAP.md`).
- Summary of phase statuses and drift findings.
- Deliverables created or updated.
- Next recommended steps.

## Done When

- [ ] 4-tier template resolution hierarchy enforced with fail-closed CRITICAL diagnostic
- [ ] Mode 1, Mode 2, Mode 3, Mode 4, and Mode 5 fully specified
- [ ] Static validation gates `RM-LINT-001` through `RM-LINT-006` defined
- [ ] Deterministic evidence inference engine (`InferredEvidenceStatus`) documented
- [ ] 100% script-free with zero `.specify/scripts/` references
- [ ] Safe structured telemetry conforming to logging standards
