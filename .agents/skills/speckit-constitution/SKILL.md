---
name: "speckit-constitution"
description: "Create or update the project constitution and co-applied companion standards (coding-standards.md and logging-standards.md) from interactive or provided principle inputs."
compatibility: "Requires spec-kit project structure with .specify/ directory"
metadata:
  author: "github-spec-kit"
  source: "templates/commands/constitution.md"
---


## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Scope Guard

This command's work is strictly scoped to establishing and updating the project's Co-Applied Governance Suite:
- **Authorized Output Files (Read/Write)**:
  1. `.specify/memory/constitution.md`
  2. `.specify/memory/coding-standards.md`
  3. `.specify/memory/logging-standards.md`
- **Prohibited Modifications**:
  - You **MUST NOT** modify any template source file under `.specify/templates/`, `.specify/presets/`, or `.specify/extensions/`.
  - You **MUST NOT** create, modify, or delete application source files, feature routes, components, tests, deployment files, or other artifacts unrelated to the co-applied governance suite.
  - Dependent Spec Kit templates and commands read governance files at runtime and must not be altered during this command's execution.
- **Handling Non-Governance Intents**:
  - Classify every part of the user input as either governance content or a separate, non-governance intent (e.g., feature implementation, code generation, refactoring, building, deployment).
  - If the input includes non-governance requests, you **MUST NOT** execute them. Extract them as deferred intents instead.
  - After completing the co-applied governance update, include a `Next Actions` section for each deferred intent. List the original intent and suggest the appropriate follow-up Spec Kit command, such as `/speckit-specify`, without invoking it.
  - If there are no non-governance intents, omit the `Next Actions` section.

## Pre-Execution Checks

**Check for extension hooks (before constitution update)**:
- Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under the `hooks.before_constitution` key
- If the YAML cannot be parsed or is invalid, do not skip silently: tell the user that `.specify/extensions.yml` could not be read (include the parser error) and that no hooks were checked, including any mandatory (`optional: false`) hooks registered there, then continue normally
- Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
- For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
  - If the hook has no `condition` field, or it is null/empty, treat the hook as executable
  - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation
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
    After emitting the block above you MUST actually invoke the hook and wait for it to finish before continuing. Run it the same way you would run the command yourself in this agent/session (the invocation may differ from the literal `{command}` id shown above, e.g. a skills-mode agent runs it as `/skill:speckit-...` or `$speckit-...`). Emitting the block alone does not run the hook.
- If no hooks are registered or `.specify/extensions.yml` does not exist, skip silently

## Outline

You are establishing or updating the project's Co-Applied Governance Suite in `.specify/memory/`:
- `.specify/memory/constitution.md`
- `.specify/memory/coding-standards.md`
- `.specify/memory/logging-standards.md`

All three documents are resolved, populated, synchronized, and persisted simultaneously in a single atomic workflow.

Follow this execution flow:

### 1. Template Resolution (Native 4-Tier Hierarchy)

For each of the three governance templates (`constitution-template`, `coding-standards-template`, `logging-standards-template`):
Resolve `<template-name>.md` natively using the 4-tier hierarchy in order:
1. Tier 1 (Overrides): `.specify/templates/overrides/<template-name>.md` (strategy: `replace`)
2. Tier 2 (Presets): `.specify/presets/<preset-id>/templates/<template-name>.md` (evaluated per `.specify/presets/.registry` in ascending priority order, respecting composition strategies: `replace`, `prepend`, `append`, `wrap`)
3. Tier 3 (Extensions): `.specify/extensions/<ext-id>/templates/<template-name>.md` (evaluated per `.specify/extensions/.registry` in ascending priority order)
4. Tier 4 (Core Fallback): `.specify/templates/<template-name>.md`
- Invariant: If a requested template is not found in any of the 4 tiers, the agent MUST fail closed and emit an error per Principle II.
- Template resolution MUST succeed for all three templates before proceeding. Do NOT write back to any source template in `.specify/templates/`, `.specify/presets/`, or `.specify/extensions/`.
- Load existing files in `.specify/memory/` if present (`constitution.md`, `coding-standards.md`, `logging-standards.md`) as the source of current project values, ratified deviations, and past amendments.

### 2. Optional Enhancement Module Activation & Precedence

Evaluate module activation states (`ENABLED` or `OMITTED`) for:
- `MODULE-A` (In-Code Open Question Pointers, Target: Principle I)
- `MODULE-B` (100% Branch Coverage Gate, Target: Principle III, Replaces: `PLAN-JUSTIFICATION-AND-SKIP-ALLOWLIST`)
- `MODULE-C` (Dispatch Is Data, Not Branches, Target: Principle IV)
- `MODULE-D` (Reproducible Builds & Deliberate Versioning, Target: Principle V)
- `MODULE-D-AOT-TRIM` (Subclause of `MODULE-D`: AOT/Trim-Safe Core Domain Logic)
- `MODULE-DOCS` (Structured Human-Facing Documentation Gate, Target: Principle VII)
- `logging_trace` (Mechanical TRACE Entry/Exit Logging in `logging-standards.md`)

**Activation Precedence**:
1. **Explicit User Input**: Enable or omit as explicitly requested in `$ARGUMENTS` or conversation.
2. **Existing Ratified State**: When updating an existing `.specify/memory/constitution.md`, preserve the module's active state if not mentioned by the user.
3. **Repository Context Inference / Default**: Default unrequested and unevidenced modules to `OMITTED`.

### 3. Structural Transformations in `constitution.md`

Transform the resolved `constitution-template` content according to active module states:
- **`MODULE-A`**:
  - If `ENABLED`: Strip opening `<!-- OPTIONAL-MODULE: MODULE-A ... -->` and closing `<!-- /OPTIONAL-MODULE: MODULE-A -->` comment lines; keep `- **Pointer-Only Code Tags**: ...` inline in Principle I.
  - If `OMITTED`: Remove the entire block including opening tag, body text, and closing tag.
- **`MODULE-B` (Mutual Exclusivity Gate)**:
  - When `module_b == ENABLED`: Principle III MUST contain `- **100% Branch Coverage Gate**:` and MUST NOT contain `- **Plan Justification & Skip Allowlist**:`. Remove the entire `<!-- DEFAULT-CLAUSE: PLAN-JUSTIFICATION-AND-SKIP-ALLOWLIST ... -->` block and retain the `MODULE-B` content with its comment tags stripped.
  - When `module_b == OMITTED`: Principle III MUST contain `- **Plan Justification & Skip Allowlist**:` and MUST NOT contain `- **100% Branch Coverage Gate**:`. Retain the default clause body, strip its `<!-- DEFAULT-CLAUSE: ... -->` and `<!-- /DEFAULT-CLAUSE: ... -->` tags, and remove the entire `MODULE-B` block.
- **`MODULE-C`**:
  - If `ENABLED`: Strip opening/closing comment tags; keep `- **Dispatch Is Data, Not Branches**: ...` inline in Principle IV.
  - If `OMITTED`: Remove the entire block completely.
- **`MODULE-D` & `MODULE-D-AOT-TRIM`**:
  - If `module_d == OMITTED`: `module_d_aot_trim` MUST be `OMITTED`. Remove the entire `MODULE-D` block (including nested `MODULE-D-AOT-TRIM`) completely.
  - If `module_d == ENABLED`: Strip opening/closing tags for `MODULE-D` and keep `- **Reproducible Builds & Deliberate Versioning**: ...` in Principle V.
  - If `module_d == ENABLED` and `module_d_aot_trim == ENABLED`: The surrounding `[Optional: ...]` brackets MUST be unwrapped so the sentence reads as normative prose (`Shared libraries consumed by constrained environments SHOULD be AOT/trim-safe...`), and strip `<!-- OPTIONAL-SUBCLAUSE: MODULE-D-AOT-TRIM ... -->` tags.
  - If `module_d == ENABLED` and `module_d_aot_trim == OMITTED`: Remove the opening subclause tag, the inner `[Optional: ...]` text, and closing subclause tag completely.
- **`MODULE-DOCS`**:
  - If `ENABLED`: Strip opening `<!-- OPTIONAL-MODULE: MODULE-DOCS ... -->` and closing `<!-- /OPTIONAL-MODULE: MODULE-DOCS -->` comment lines; keep `- **Structured Human-Facing Documentation Gate**: ...` inline in Principle VII.
  - If `OMITTED`: Remove the entire block including opening tag, body text, and closing tag.
- **Strip All Residual Markers**: Strip all `OPTIONAL-MODULE`, `OPTIONAL-SUBCLAUSE`, and `DEFAULT-CLAUSE` HTML comment lines.

### 4. Placeholder Value Merge & Project Identity Synchronization

Discover and substitute all 26 `[ALL_CAPS_IDENTIFIER]` slots:
- **`constitution.md` (8 slots)**: `[PROJECT_NAME]`, `[PRIMARY_SOURCE]`, `[SECONDARY_SOURCE]`, `[TERTIARY_SOURCE]`, `[ACCEPTANCE_GATE_COMMANDS]`, `[CONSTITUTION_VERSION]`, `[RATIFICATION_DATE]`, `[LAST_AMENDED_DATE]`
- **`coding-standards.md` (12 slots)**: `[PROJECT_NAME]`, `[PRIMARY_LANGUAGE_AND_RUNTIME]`, `[BUILD_AND_LINTER_COMMANDS]`, `[DEPENDENCY_AND_LOCKFILE_CONVENTIONS]`, `[PROJECT_STRUCTURE_CONVENTIONS]`, `[BOUNDARY_ENFORCEMENT_MECHANISM]`, `[ERROR_RESULT_TYPES]`, `[DEFECT_INVARIANT_MECHANISM]`, `[IMMUTABLE_SNAPSHOT_AND_ID_CONVENTIONS]`, `[TEST_FRAMEWORK_CONVENTIONS]`, `[NAMING_CONVENTIONS]`, `[HUMAN_DOCS_CONVENTIONS]`
- **`logging-standards.md` (6 slots)**: `[PROJECT_NAME]`, `[LOGGING_FRAMEWORK]`, `[LOG_SINKS_AND_FORMATS]`, `[CORRELATION_ID_SCHEMA]`, `[SENSITIVE_DATA_REDACTION_MECHANISM]`, `[RETENTION_AND_SAMPLING_POLICY]`

**Substitution Rules**:
1. **Project Name Synchronization**: `project_name` (`[PROJECT_NAME]`): Non-empty string; MUST be identical across the H1 headers (`# <project_name> Constitution`, `# <project_name> Coding Standards`, `# <project_name> Logging Standards`) and inline project references in all three files.
2. **Value Merge Priority**:
   - (1) Explicit User Input in conversation or `$ARGUMENTS`
   - (2) Existing Ratified Governance Values in `.specify/memory/` (preserve `RATIFICATION_DATE`, `Recorded Deviations`, and established project conventions)
   - (3) Repository Evidence (README, docs, package manifests, linter configs, toolchain setups)
   - (4) Explicit `TODO(<FIELD_NAME>): <explanation>` if undetermined (never invent guesses or leave raw brackets)
3. **Governance Dates & Versioning**:
   - `RATIFICATION_DATE`: Original adoption date (`YYYY-MM-DD`). Must be preserved across updates.
   - `LAST_AMENDED_DATE`: Current date (`YYYY-MM-DD`) if modified, otherwise retain previous date.
   - `CONSTITUTION_VERSION`: Semantic version (`MAJOR.MINOR.PATCH`):
     - `MAJOR`: Incompatible principle removals or redefinitions.
     - `MINOR`: New principles or materially expanded gates.
     - `PATCH`: Clarifications, typos, non-semantic refinements.
4. **Telemetry Configuration**: In `logging-standards.md`, reflect whether mechanical `TRACE` logging is enabled or omitted.

### 5. Constitutional Conflict Resolution Gate & Recorded Deviations

- Core Principles I–VII in `constitution-template.md` are non-negotiable.
- If a project convention or user instruction contradicts a Core Principle:
  1. Do NOT silently delete, weaken, or contradict the Core Principle in `constitution.md`.
  2. Surface the conflict explicitly and either:
     - **Option A (Align Standards)**: Align `coding-standards.md` and `logging-standards.md` to comply with the Core Principle and document required codebase remediation.
     - **Option B (Ratified Deviation)**: Record an explicit human-ratified deviation under `## Recorded Deviations` in `constitution.md` with all 5 mandatory fields:
       1. `Principle violated`
       2. `Ratifying human authority`
       3. `Rationale`
       4. `Compensating control`
       5. `Known gap and documentation link`
- Existing valid entries under `## Recorded Deviations` MUST be preserved when amending the constitution.

### 6. Sync Impact Report Generation

Format the top HTML comment in `.specify/memory/constitution.md` with the latest amendment summary (must only record the latest amendment, do not accumulate historical amendment logs inside the file):

```markdown
<!--
Sync Impact Report (Latest Amendment Only — Do Not Accumulate History):
- Version Change: <old_version> -> <new_version>
- Modified Principles: <summary of principle changes or "None (preserved Principles I–VII)">
- Modified Sections: <list of modified sections>
- Optional Modules: MODULE-A: <ENABLED|OMITTED>, MODULE-B: <ENABLED|OMITTED>, MODULE-C: <ENABLED|OMITTED>, MODULE-D: <ENABLED|OMITTED> (MODULE-D-AOT-TRIM: <ENABLED|OMITTED>), MODULE-DOCS: <ENABLED|OMITTED>, TRACE Logging: <ENABLED|OMITTED>
- Companion Standards: coding-standards.md (<created|updated|unchanged>), logging-standards.md (<created|updated|unchanged>)
- Rationale: <concise rationale for initialization or amendment>
- Deferred TODOs: <None or list of TODO(FIELD_NAME) items>
-->
```

### 7. Pre-Write Validation Gate

Before persisting any files, verify:
1. All three files (`constitution.md`, `coding-standards.md`, `logging-standards.md`) have valid non-empty content.
2. `[PROJECT_NAME]` is identical across all three H1 titles.
3. Regex search `\[[A-Z0-9_]+\]` across all three files returns **0** matches.
4. Regex search `<!-- /?(OPTIONAL-MODULE|OPTIONAL-SUBCLAUSE|DEFAULT-CLAUSE)` in `constitution.md` returns **0** matches.
5. Dates match `YYYY-MM-DD` and `CONSTITUTION_VERSION` matches the `Sync Impact Report`.
6. Principle III mutual exclusivity: Contains either `- **Plan Justification & Skip Allowlist**:` OR `- **100% Branch Coverage Gate**:`, never both.

### 8. Atomic Persistence & Completion Report

1. Write `.specify/memory/constitution.md`, `.specify/memory/coding-standards.md`, and `.specify/memory/logging-standards.md`.
2. Output a summary to the user:
   - Version change and bump rationale.
   - Status of all 3 governance files.
   - Optional Enhancement Modules configuration.
   - Any `TODO(<FIELD_NAME>)` items requiring follow-up.
   - Suggested git commit message (e.g., `docs: co-apply governance suite vX.Y.Z`).
   - A `Next Actions` section listing any deferred non-governance intents and recommended follow-up commands (e.g., `/speckit-specify`).

## Post-Execution Checks

**Check for extension hooks (after constitution update)**:
Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under the `hooks.after_constitution` key
- If the YAML cannot be parsed or is invalid, do not skip silently: tell the user that `.specify/extensions.yml` could not be read (include the parser error) and that no hooks were checked, including any mandatory (`optional: false`) hooks registered there, then continue normally
- Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
- For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
  - If the hook has no `condition` field, or it is null/empty, treat the hook as executable
  - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation
- When constructing command invocations from hook command names, replace dots (`.`) with hyphens (`-`). For example, `speckit.git.commit` → `/speckit-git-commit`.
- For each executable hook, output the following based on its `optional` flag:
  - **Optional hook** (`optional: true`):
    ```
    ## Extension Hooks

    **Optional Hook**: {extension}
    Command: `/{command}`
    Description: {description}

    Prompt: {prompt}
    To execute: `/{command}`
    ```
  - **Mandatory hook** (`optional: false`):
    ```
    ## Extension Hooks

    **Automatic Hook**: {extension}
    Executing: `/{command}`
    EXECUTE_COMMAND: {command}
    ```
    After emitting the block above you MUST actually invoke the hook and wait for it to finish before continuing. Run it the same way you would run the command yourself in this agent/session (the invocation may differ from the literal `{command}` id shown above, e.g. a skills-mode agent runs it as `/skill:speckit-...` or `$speckit-...`). Emitting the block alone does not run the hook.
- If no hooks are registered or `.specify/extensions.yml` does not exist, skip silently
