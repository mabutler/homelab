# Quickstart Validation Guide: Constitution v2.0.0 Codebase Audit and Alignment

**Feature**: `012-constitution-codebase-audit`  
**Date**: 2026-11-05

---

## Prerequisites

- Linux workstation or target host (`fidelacchius`) with:
  - `bash` (5.x)
  - `shellcheck`
  - `ansible-lint` (with `ansible-core`)
  - `git` and standard POSIX utilities (`grep`, `test`)

---

## 1. Run Unified Constitutional Pre-PR Gate (`AUD-01`, `AUD-02`, `AUD-08`)

From the repository root (`/home/admin/projects/homelab2`):

```bash
bash -n scripts/*.sh bootstrap-speckit.sh && \
shellcheck scripts/*.sh bootstrap-speckit.sh && \
ansible-lint
```

**Expected Outcome**:
- `bash -n` exits `0` with no syntax errors.
- `shellcheck` exits `0` with zero warnings or info diagnostics.
- `ansible-lint` exits `0` with `0 failure(s), 0 warning(s)` under the `production` profile, excluding `.worktrees/` and resolving all roles in `ansible/roles/`.

---

## 2. Verify Documentation & Epistemic Hygiene (`AUD-03`..`AUD-07`)

Run the following verification checks from the repository root:

```bash
# AUD-03: Zero machine-specific file:///C: URIs
! grep -rn "file:///C:" README.md ROADMAP.md docs/ reference/

# AUD-04: Zero ephemeral spec paths or FR-XXX citations outside specs/
! grep -rnE "FR-[0-9]{3}|specs/[0-9]{3}-" README.md ROADMAP.md docs/ scripts/ ansible/

# AUD-05: Governance version v2.0.0 alignment
! grep -rn "v1\.1\.0" README.md ROADMAP.md docs/ && \
grep -q "v2.0.0" ROADMAP.md && \
grep -q "v2.0.0" docs/roadmap.md

# AUD-06: Centralized open questions registry exists
test -s reference/open-questions.md

# AUD-07: Canonical 4 sections in README.md
grep -q "Project Overview & Phase Architecture" README.md && \
grep -q "Getting Started / Convergence Quickstart" README.md && \
grep -q "CLI / Skill / Acceptance Verification Reference" README.md && \
grep -q "Configuration & Governance Verification" README.md
```

**Expected Outcome**:
- Every command above exits with code `0`.
- See [contracts/verification-gate-contract.md](contracts/verification-gate-contract.md) for the complete assertion specification and [data-model.md](data-model.md) for the role variable mapping table.
