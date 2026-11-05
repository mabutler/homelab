---
name: "speckit-bootstrap"
description: "Verify installation integrity, manage non-destructive upgrades, detect configuration drift, and initialize project governance."
compatibility: "Requires spec-kit project structure with .specify/ directory"
metadata:
  author: "github-spec-kit"
  source: "templates/commands/bootstrap.md"
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Scope Guard

This command manages the lifecycle, installation integrity, non-destructive upgrades, and governance initialization of Spec Kit within the target repository.

### Protected User-State Rule

The following paths belong strictly to the user and the project's living governance:
- `ROADMAP.md` (Strategic multi-phase roadmap at repository root)
- `.specify/memory/constitution.md`
- `.specify/memory/coding-standards.md`
- `.specify/memory/logging-standards.md`
- `.specify/templates/overrides/**`
- `.specify/feature.json` and `specs/**`
- `.agents/agents/*.local.md` and custom non-canonical agent profiles
- Custom skills in `.agents/skills/`

**Invariant**: The bootstrapper MUST "never overwrite or delete under any circumstances, even when --force / -Force is passed".

---

## Command Invocations & Arguments

```text
/speckit-bootstrap [<target-repo>] [--upgrade] [--check|--dry-run] [--force] [--init-governance] [--source=<source-repo>]
```

| Parameter / Flag | Type | Description |
|------------------|------|-------------|
| `<target-repo>` | Positional String | Path to target repository. Defaults to current working directory (`.`). |
| `--upgrade` | Flag | Performs upgrade against the source bundle, updating unmodified managed files. |
| `--check` or `--dry-run` | Flag | Read-only inspection. Computes file classification plan without modifying disk. |
| `--force` | Flag | Overwrite drifted managed files (Protected User State remains untouched). |
| `--init-governance` | Flag | After bootstrap checks complete, invokes `/speckit-constitution` on target repo. |
| `--source=<source-repo>` | Option | Source toolkit directory when upgrading another repository from outside. |

---

## File Action Classification State Machine

Every target file is evaluated against the source bundle and install manifest using 6 mutually exclusive states:

1. **`CREATE`**: File exists in the source bundle but is absent from the target repository.
   - Action: Copy source file to target path.
2. **`UPGRADE`**: File exists in target repository, matches the manifest digest (or target has not drifted from last known install), and differs from upstream source.
   - Action: Update target file with upstream source content.
3. **`PRESERVE_USER_STATE`**: File is present on the Protected User-State Allowlist.
   - Action: Preserve untouched without modification or warning under all circumstances.
4. **`SKIP_DRIFTED`**: File exists in target repository with checksum differing from both the recorded manifest digest and upstream source (local user customization).
   - Action: Skip modification by default; log structured `WARN` diagnostic. If `--force` is specified, overwrite with upstream source.
5. **`REMOVE_OBSOLETE`**: File is present in target repository or target manifest as an obsolete legacy asset (such as legacy automation scripts).
   - Action: Safely delete file from disk and remove from manifests.
6. **`UNCHANGED`**: Target file content matches upstream source bundle bit-for-bit.
   - Action: No disk mutation required.

---

## Execution Modes

### Mode A: Self-Check / Post-Seed Verification (Default)

Triggered when executed without `--upgrade` or `--check`:
1. **Asset Scan**:
   - Inspect target repository for all canonical managed files:
     - Templates: `.specify/templates/*.md` (including `roadmap-template.md`)
     - Presets: `.specify/presets/.registry` and packages (`.specify/presets/base-governance/`)
     - Extensions: `.specify/extensions/.registry` and packages (`.specify/extensions/speckit-orchestrator/`)
     - Workflows: `.specify/workflows/workflow-registry.json`, `.specify/workflows/speckit/workflow.yml`
     - Integrations: `.specify/integrations/speckit.manifest.json`, `agy.manifest.json`, `speckit-bootstrap.manifest.json`
     - Configuration: `.specify/extensions.yml`, `.specify/init-options.json`, `.specify/integration.json`, `.specify/.gitignore`
     - Role Profiles: `.agents/agents/speckit-reasoner.md`, `.agents/agents/speckit-executor.md`
     - Skills: All 12 skills in `.agents/skills/` (including `speckit-roadmap`)
2. **Obsolete Script Detection & Removal**:
   - Check if legacy `scripts/` directory exists under `.specify`.
   - If found, delete the legacy directory and purge any obsolete script entries from `.specify/integrations/speckit.manifest.json`.
3. **Configuration & Gitignore Idempotent Merge**:
   - Ensure `<target-repo>/.gitignore` exists and contains `.agents/agents/*.local.md`.
   - Ensure `<target-repo>/.specify/extensions.yml` contains `speckit.orchestrate` under `hooks.after_specify`:
     ```yaml
     schema_version: "1.0"
     hooks:
       after_specify:
         - extension: "speckit-orchestrator"
           command: "speckit.orchestrate"
           description: "Coordinate context-isolated subagents across clarify, plan, tasks, analyze, implement, and converge"
           prompt: "Specification complete and validated. Run /speckit-orchestrate to run through design and tasks (pauses before implementation for review), or /speckit-orchestrate --continue to run continuously through the end."
           enabled: true
           optional: true
     ```
     Preserve all existing custom hooks during merge.
4. **Manifest Synchronization**:
   - Calculate SHA-256 digests (`sha256:<hex>`) and byte sizes for all managed files.
   - Generate or update `.specify/integrations/speckit-bootstrap.manifest.json` conforming to `manifest-schema.json`.
   - Ensure `speckit.manifest.json` and `agy.manifest.json` are synchronized with 0 script entries.
5. **Governance State Check**:
   - Inspect `.specify/memory/` for `constitution.md`, `coding-standards.md`, and `logging-standards.md`.
   - If missing, report status and recommend running `/speckit-constitution`.

### Mode B: Upgrade & Drift Detection (`--upgrade` / `--check` / `--dry-run`)

Triggered when `--upgrade`, `--check`, or `--dry-run` is passed:
1. Locate source toolkit bundle (via `--source=<source-repo>` or current toolkit directory).
2. Read target manifest `.specify/integrations/speckit-bootstrap.manifest.json` if present.
3. Compute 6-state classification for every managed file across source and target.
4. If `--check` or `--dry-run`:
   - Output structured classification table without mutating disk.
5. If executing mutations:
   - Create `CREATE` files.
   - Update `UPGRADE` files.
   - Preserve `PRESERVE_USER_STATE` files.
   - For `SKIP_DRIFTED` files: skip modification and emit `WARN` diagnostics unless `--force` is supplied.
   - Delete `REMOVE_OBSOLETE` files.
   - Write updated `.specify/integrations/speckit-bootstrap.manifest.json`.

### Mode C: Governance Initialization (`--init-governance`)

Triggered when `--init-governance` is specified or explicitly requested:
1. Complete Mode A verification steps.
2. Inspect `.specify/memory/`.
3. Invoke `/speckit-constitution` (or dispatch subagent to run `.agents/skills/speckit-constitution/SKILL.md`) against target repository to ratify project constitution and companion standards.

---

## Output Report Format

```markdown
### Spec Kit Bootstrap Report

**Target Repository**: `<path>`  
**Execution Mode**: `<Self-Check | Upgrade | Dry-Run>`  
**Source Bundle Version**: `1.4.0`  

#### Execution Summary
- **Created**: <N> files
- **Upgraded**: <N> files
- **Unchanged**: <N> files
- **Preserved (User State)**: <N> files
- **Skipped (Local Drift)**: <N> files
- **Obsolete Removed**: <N> files

#### Diagnostics & Warnings
> [!NOTE]
> All managed assets verified cleanly.

#### Handoff & Recommended Next Steps
- Governance Suite: <Ratified | Uninitialized>
- Next Recommended Command: `/speckit-specify <feature-description>`
```
