# Contract: Constitution v2.0.0 Static Verification & Hygiene Gate

**Feature**: `012-constitution-codebase-audit`  
**Contract ID**: `AUD-01..08`  
**Authority**: `.specify/memory/constitution.md` (v2.0.0), `.specify/memory/coding-standards.md`

---

## 1. Verification Assertion Matrix

Every requirement in `spec.md` (`FR-001` through `FR-013`) maps to a deterministic, unprivileged static verification assertion that MUST exit with code `0` and zero warnings:

| Assertion ID | Requirement | Verification Command (from Repository Root) | Expected Outcome |
|---|---|---|---|
| **AUD-01** | `FR-007`, `FR-013`, `SC-001` | `bash -n scripts/*.sh bootstrap-speckit.sh && shellcheck scripts/*.sh bootstrap-speckit.sh` | Exit code `0`; zero stdout/stderr warnings across all shell scripts. |
| **AUD-02** | `FR-001`..`FR-006`, `FR-013`, `SC-002` | `ansible-lint` | Exit code `0`; `0 failure(s), 0 warning(s)` under `production` profile; `.worktrees/` excluded; all roles resolved. |
| **AUD-03** | `FR-008`, `SC-003` | `! grep -rn "file:///C:" README.md ROADMAP.md docs/ reference/` | Exit code `0` (zero matches of machine-specific `file:///C:` URIs). |
| **AUD-04** | `FR-011`, `SC-004` | `! grep -rnE "FR-[0-9]{3}|specs/[0-9]{3}-" README.md ROADMAP.md docs/ scripts/ ansible/` | Exit code `0` (zero citations of `FR-XXX` or `specs/NNN-*` outside `specs/`). |
| **AUD-05** | `FR-009`, `SC-005` | `! grep -rn "v1\.1\.0" README.md ROADMAP.md docs/` && `grep -q "v2.0.0" ROADMAP.md` && `grep -q "v2.0.0" docs/roadmap.md` | Exit code `0` (all governance version citations updated to `v2.0.0`). |
| **AUD-06** | `FR-010`, `SC-007` | `test -s reference/open-questions.md` | Exit code `0` (`reference/open-questions.md` exists and is non-empty). |
| **AUD-07** | `FR-012`, `SC-006` | Verify 4 canonical section headings in `README.md`:<br>1. `Project Overview & Phase Architecture`<br>2. `Getting Started / Convergence Quickstart`<br>3. `CLI / Skill / Acceptance Verification Reference`<br>4. `Configuration & Governance Verification` | Exit code `0` (all 4 canonical headings present and Phase 1–8 status documented). |
| **AUD-08** | `FR-013`, `SC-008` | `bash -n scripts/*.sh && shellcheck scripts/*.sh && ansible-lint` | Exit code `0` (unified Constitutional Pre-PR Verification Gate passes cleanly). |

---

## 2. Behavioral & Safety Invariants

1. **Zero Automated Test Files (Constitutional Principle III)**:
   - No unit test files, test directories (`tests/`), mock frameworks, or test runners may be created. All verification relies strictly on static analysis (`bash -n`, `shellcheck`, `ansible-lint`) and existing acceptance scripts (`scripts/verify-phase*.sh`).
2. **Protected Toolchain & Linter Strictness (Constitutional Principle V)**:
   - `.ansible-lint` MUST retain `profile: production` and `.shellcheckrc` MUST retain `shell=bash`. Global rule suppressions (`skip_list`) that hide code defects are forbidden.
3. **Backward-Compatible CLI Behavior**:
   - `scripts/apply-phase7-antigravity.sh` and `scripts/apply-phase7-antigravity.ps1` MUST continue enforcing `--confirm-target-ready` / `-ConfirmTargetReady` with exit code `3` when omitted, changing only the diagnostic message citation from `FR-011` to Constitutional Principle VI (`Verify Before Mutate/Destroy` / `AG-001..008`).
