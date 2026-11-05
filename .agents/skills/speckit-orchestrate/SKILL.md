---
name: "speckit-orchestrate"
description: "Coordinate context-isolated subagents across clarify, plan, tasks, analyze, implement, and converge"
compatibility: "Requires spec-kit project structure with .specify/ directory"
metadata:
  author: "github-spec-kit"
  source: "templates/commands/orchestrate.md"
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Check for extension hooks (before orchestration)**:
- Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under the `hooks.before_orchestrate` key.
- If the YAML cannot be parsed or is invalid, do not skip silently: tell the user that `.specify/extensions.yml` could not be read (include the parser error) and that no hooks were checked, including any mandatory (`optional: false`) hooks registered there, then continue normally.
- Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
- For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
  - If the hook has no `condition` field, or it is null/empty, treat the hook as executable.
  - If the hook defines a non-empty `condition`, skip the hook.
- When constructing command invocations from hook command names, replace dots (`.`) with hyphens (`-`).
- For each executable hook, output the prompt or emit `EXECUTE_COMMAND:` and run mandatory hooks as required.
- If no hooks are registered or `.specify/extensions.yml` does not exist, skip silently.

## Anti-Recursion Invariant

When running as a subagent or child process (`ORCHESTRATOR_CHILD=true`):
- NEVER invoke `/speckit-orchestrate` or trigger `hooks.after_specify` recursively.
- Always propagate `ORCHESTRATOR_CHILD=true` down to any subagent dispatch payloads.

---

## Outline

### 1. Argument Parsing & Runtime Scope Resolution

Parse `$ARGUMENTS` for execution-scope flags, overrides, and free-form feature description:
- **Default Checkpoint Policy**: Pauses cleanly after `analyze` before code implementation (`implement`), allowing human review of `plan.md` and `tasks.md`.
- `--continue` / `--continuous` (aliases: `--no-pause`, `--auto-implement`): Bypasses the pre-implementation pause, running continuously through the end (`converge`). Equivalent to `--until=converge`.
- `--pause-before-implement`: Explicit alias for default behavior (halts cleanly after `analyze` before `implement`). Retained for backward compatibility.
- `--until=<stage>`: Halts cleanly immediately after `<stage>` completes (`clarify`, `plan`, `tasks`, `analyze`, `implement`, `converge`). Defaults to `analyze` (pausing before implement) unless `--continue`/`--continuous` or `--resume` is specified.
- `--from=<stage>`: Forces execution to start at `<stage>` (`specify`, `clarify`, `plan`, `tasks`, `analyze`, `implement`, `converge`), regenerating artifacts even if they exist.
- `--resume`: Resumes from the first incomplete stage on an existing feature. When resuming after the pre-implementation pause (`analyze` complete, `implement` pending), resumes directly into Stage 6 (`implement`) and runs through `converge` (unless constrained by `--until=<stage>`).
- `--clarify`: Forces full `speckit-clarify` subagent pass even if `[NEEDS CLARIFICATION]` marker count is 0.
- `--model=<tier>`: Explicit subagent model override (`inherit`, `pro`, `flash`, `flash_lite`, `opus`, `sonnet`).
- `--override-ceiling`: Allows escalating subagents to high-reasoning models (`pro`, `opus`) even when session ceiling is standard (`flash`, `sonnet`).
- `FEATURE_DESCRIPTION`: Any remaining non-flag text tokens.

### 2. Feature Directory & Authoritative State Resolution

Resolve authoritative feature context:
1. Check `SPECIFY_FEATURE_DIRECTORY` environment variable, or read `.specify/feature.json` (`feature_directory`).
2. If `feature_directory` exists:
   - Resolve absolute path: e.g. `/home/admin/projects/spec-kit-testing/specs/<feature-name>`.
   - Verify existence of `spec.md`.
3. If neither resolves to an existing feature directory:
   - If `FEATURE_DESCRIPTION` is provided: Stage 1 (`specify`) will initialize a new feature directory.
   - If `FEATURE_DESCRIPTION` is empty: **FAIL CLOSED** (`FAILED_CLOSED`). Log `CRITICAL` diagnostic:
     `"CRITICAL: No active feature found in .specify/feature.json or SPECIFY_FEATURE_DIRECTORY, and no feature description provided. Provide a feature description to /speckit-orchestrate <description> or run /speckit-specify first."`
     Halt execution immediately.
4. Pass `SPECIFY_FEATURE_NO_PERSIST=1` to all downstream child stage invocations after feature directory creation.

### 3. Governance Suite Adherence & Principle III Enforcement

Load and enforce project governance suite:
- `.specify/memory/constitution.md`
- `.specify/memory/coding-standards.md`
- `.specify/memory/logging-standards.md`

**NON-NEGOTIABLE PRINCIPLE III ENFORCEMENT**:
- Automated test generation is disabled repository-wide.
- Subagents MUST NOT generate unit test files, integration test files, test directories, or test tasks.
- All quality verification relies exclusively on static syntax inspection, schema validation, and declarative gates.

### 4. Agent Profile Hierarchy & Session Model Ceiling

Resolve subagent definitions using the 5-level override hierarchy:
1. **Runtime Flag**: `--model=<tier>` or `--agent=<name>` in `$ARGUMENTS`.
2. **Stage Local Override**: `.agents/agents/speckit-<stage>.local.md` (gitignored).
3. **Stage Tracked Override**: `.agents/agents/speckit-<stage>.md`.
4. **Role Local Override**: `.agents/agents/speckit-<role>.local.md` (gitignored).
5. **Role Tracked Default**: `.agents/agents/speckit-<role>.md` (`speckit-reasoner.md` for `reasoning`, `speckit-executor.md` for `execution`).

#### Role Capability Tiers
- **High-Reasoning (`speckit-reasoner`)**: `clarify`, `plan`, `analyze`, `converge`, self-heal remediation, and convergence retry escalations.
- **Standard/Fast Execution (`speckit-executor`)**: `specify`, `tasks`, and initial `implement` pass 1.

#### Session Model Ceiling Algorithm
- Detect active session model tier:
  - `high_reasoning`: Gemini Argon / Gemini Pro, Claude Opus.
  - `standard_execution`: Gemini Flash / Flash Lite, Claude Sonnet / Haiku.
- If session tier is `high_reasoning`:
  - `speckit-reasoner` runs with `Model: "inherit"` (or `"pro"` / `"opus"`).
  - `speckit-executor` steps down to `Model: "flash"` / `"sonnet"`.
- If session tier is `standard_execution`:
  - `speckit-reasoner` is capped at session ceiling (`Model: "inherit"` / `"flash"` / `"sonnet"`) unless `override_ceiling: true` or `--override-ceiling` is passed.
  - `speckit-executor` runs with `Model: "inherit"` / `"flash"`.

### 5. Subagent Registration & Dispatch Protocol

Register subagent personas using `define_subagent` if not already defined:
- `Name`: `"speckit-reasoner"` or `"speckit-executor"` (or stage-specific name).
- `Description`: Extracted from YAML frontmatter `description`.
- `SystemPrompt`: Extracted from markdown body of agent profile.
- `EnableWriteTools`: `true` for write stages; `false` for read-only `analyze`.
- `EnableSubagentTools`: `false` by default (only `true` for `implement` if coordinating disjoint parallel workers).
- `Workspace`: `"inherit"`.

#### Mandatory Subagent Prompt Payload
When calling `invoke_subagent`, the prompt MUST include:
```markdown
## Stage Execution Directive: {STAGE_NAME}

1. Target Skill: Read and execute {SKILL_FILE_PATH}
2. Feature Context:
   - SPECIFY_FEATURE_DIRECTORY: {FEATURE_DIR}
   - .specify/feature.json: {"feature_directory": "{REL_FEATURE_DIR}"}
   - SPECIFY_FEATURE_NO_PERSIST=1 (for all stages after initial specify)
3. Governance Suite Adherence (Non-Negotiable):
   - Enforce .specify/memory/constitution.md (specifically Principle III: ZERO automated test files, test directories, or test tasks).
   - Enforce .specify/memory/coding-standards.md and .specify/memory/logging-standards.md.
4. Hook Anti-Recursion Guard:
   - ORCHESTRATOR_CHILD=true: Do NOT invoke /speckit-orchestrate from any hooks.
5. Required Completion Report:
   Return structured summary:
   - STAGE_STATUS: SUCCESS | PAUSED_FOR_USER | FAILED
   - ARTIFACTS_TOUCHED: <comma-separated list of paths>
   - GATE_DATA: <checklist results, finding counts, or convergence outcome>
   - DIAGNOSTICS: <summary of log messages>
```

### 6. Pipeline Execution State Machine

Execute stages sequentially under single-writer serialization:

#### Stage 1: Specify
- **Agent**: `speckit-executor` (`execution`)
- **Skill**: `.agents/skills/speckit-specify/SKILL.md`
- **Condition**: Run if `spec.md` is missing, or `--from=specify` is specified.
- **Check**: Verify `spec.md` and `checklists/requirements.md` created.
- **Anti-Recursion**: Pass `ORCHESTRATOR_CHILD=true` so `hooks.after_specify` does not re-trigger orchestrator.
- Check `--until=specify`: if true, halt cleanly.

#### Stage 2: Clarify Gate
- **Agent**: `speckit-reasoner` (`reasoning`)
- **Inspection**:
  - Scan `spec.md` for occurrences of `[NEEDS CLARIFICATION]`.
  - Scan `checklists/requirements.md` for unchecked `- [ ]` items.
  - Check if `--clarify` flag was set.
- **Gate Evaluation**:
  - If `[NEEDS CLARIFICATION]` > 0, checklist has unchecked items, or `--clarify` is true:
    - Run `speckit-clarify` subagent to generate targeted questions.
    - If ambiguities require human input: **PAUSE FOR USER** (`PAUSED_FOR_USER`).
      Present clarification questions and stop without proceeding to `plan`.
  - If 0 ambiguities and checklist PASS: mark Clarify Gate `PASSED`.
- Check `--until=clarify`: if true, halt cleanly.

#### Stage 3: Plan
- **Agent**: `speckit-reasoner` (`reasoning`)
- **Skill**: `.agents/skills/speckit-plan/SKILL.md`
- **Condition**: Run if `plan.md` is missing/empty, or `--from=plan` (or earlier) was specified. Skip if `plan.md` already exists and is non-empty.
- **Verification**: Verify `plan.md`, `research.md`, `data-model.md`, `quickstart.md`, and contracts exist.
- Check `--until=plan`: if true, halt cleanly.

#### Stage 4: Tasks
- **Agent**: `speckit-executor` (`execution`)
- **Skill**: `.agents/skills/speckit-tasks/SKILL.md`
- **Condition**: Run if `tasks.md` is missing/empty, or `--from=tasks` (or earlier) was specified. Skip if `tasks.md` already exists and is non-empty.
- **Verification**: Verify `tasks.md` contains dependency-ordered phases and tasks.
- Check `--until=tasks`: if true, halt cleanly.

#### Stage 5: Analyze & Self-Heal Gate
- **Agent**: `speckit-reasoner` (`reasoning`)
- **Skill**: `.agents/skills/speckit-analyze/SKILL.md`
- **Execution**: Run `speckit-analyze` to perform non-destructive consistency check across `spec.md`, `plan.md`, and `tasks.md`.
- **Gate Evaluation**:
  - If `CRITICAL > 0` or `HIGH > 0`:
    - **FAIL CLOSED** (`FAILED_CLOSED`). Halt immediately. Output blocking findings table.
  - If `MEDIUM > 0` or `LOW > 0` (drift detected):
    - If `heal_iteration < 2`:
      - Dispatch remediation subagent (`speckit-reasoner`) to align `plan.md` and/or `tasks.md` with `spec.md`.
      - Increment `heal_iteration`.
      - Re-run `speckit-analyze`.
    - If `heal_iteration >= 2` and drift persists:
      - **FAIL CLOSED** (`FAILED_CLOSED`). Halt and report unresolved drift.
  - If findings == 0:
    - Mark gate `PASSED` (or `SELF_HEALED` if remediated).
- **Pre-Implementation Checkpoint (Default)**:
  - Check whether to halt before Stage 6 (`implement`):
    - If `--continue` / `--continuous` / `--no-pause` / `--auto-implement` is passed, OR `--until=implement` or `--until=converge` was explicitly specified, OR execution was triggered via `--resume`:
      - Proceed to Stage 6: `implement`.
    - Otherwise (Default behavior, or if `--pause-before-implement` or `--until=analyze` was passed):
      - **PAUSE FOR USER** (`PAUSED_AT_CHECKPOINT`).
      - Instruct user to review `plan.md` and `tasks.md`, then resume with `/speckit-orchestrate --resume` (or `/speckit-orchestrate --continue`).

#### Stage 6: Implement
- **Agent**: `speckit-executor` (`execution` for pass 1) / `speckit-reasoner` (`reasoning` for retries 2..3)
- **Skill**: `.agents/skills/speckit-implement/SKILL.md`
- **Safe Concurrency & Single Coordinator**:
  - Sequential tasks execute in dependency order.
  - Parallel tasks marked `[P]` within the same phase are validated for mutually disjoint file paths before concurrent dispatch.
  - All `tasks.md` checkbox markers (`- [x]`) are updated exclusively by the coordinator or executing subagent under single-writer serialization.
- Check `--until=implement`: if true, halt cleanly.

#### Stage 7: Converge
- **Agent**: `speckit-reasoner` (`reasoning`)
- **Skill**: `.agents/skills/speckit-converge/SKILL.md`
- **Execution & Retry Loop**:
  - Run `speckit-converge` to inspect repository against `spec.md`, `plan.md`, and `tasks.md`.
  - If outcome == `converged`:
    - Pipeline is complete! Overall status: `CONVERGED`.
  - If outcome == `tasks_appended`:
    - If `converge_iteration < 3`:
      - Increment `converge_iteration`.
      - Escalate to `speckit-reasoner` (High-Reasoning model) to execute the newly appended `## Phase N: Convergence` tasks in `tasks.md` via `speckit-implement`.
      - Re-run Stage 7 `converge`.
    - If `converge_iteration >= 3` and convergence still not reached:
      - **FAIL CLOSED** (`FAILED_CLOSED`). Log `CRITICAL` diagnostic and report unbuilt work.

---

## Post-Execution Hooks

Check if `.specify/extensions.yml` exists in project root.
- Read entries under `hooks.after_orchestrate` (if any).
- Filter out hooks with `enabled: false`.
- If mandatory hooks exist (`optional: false`), emit `EXECUTE_COMMAND:` and execute them.
- If optional hooks exist (`optional: true`), display prompt and command.

---

## Completion Report & Pipeline Summary

Output the structured Pipeline Execution Summary:

```markdown
## Pipeline Execution Summary

- **Feature Directory**: `{FEATURE_DIRECTORY}`
- **Session Model Ceiling**: `{SESSION_MODEL} ({SESSION_TIER})`
- **Overall Pipeline Status**: `{OVERALL_STATUS}`

| Stage | Status | Agent Profile | Resolved Model Tier | Iterations | Artifacts Verified / Modified |
|-------|--------|---------------|---------------------|------------|-------------------------------|
| 1. Specify | {STATUS} | {AGENT} | {MODEL} | {N} | `spec.md`, `checklists/requirements.md` |
| 2. Clarify Gate | {STATUS} | {AGENT} | {MODEL} | {N} | `spec.md`, `checklists/requirements.md` |
| 3. Plan | {STATUS} | {AGENT} | {MODEL} | {N} | `plan.md`, `research.md`, `data-model.md`, `quickstart.md`, `contracts/` |
| 4. Tasks | {STATUS} | {AGENT} | {MODEL} | {N} | `tasks.md` |
| 5. Analyze Gate | {STATUS} | {AGENT} | {MODEL} | {N/2} | `plan.md`, `tasks.md` (Analysis Report) |
| 6. Implement | {STATUS} | {AGENT} | {MODEL} | {N/3} | `tasks.md` + repository files |
| 7. Converge | {STATUS} | {AGENT} | {MODEL} | {N/3} | `tasks.md` (`converged` / `tasks_appended`) |

### Next Action
- {ACTIONABLE_NEXT_STEP}
```
