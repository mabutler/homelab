# [PROJECT NAME] Roadmap

<!--
Template Resolution Hierarchy & FeatureContext Specification:
This template is resolved by agent skills using the native 4-tier template resolution hierarchy:
- Tier 1 (Overrides): .specify/templates/overrides/roadmap-template.md
- Tier 2 (Presets): .specify/presets/<preset-id>/templates/roadmap-template.md (evaluated per .specify/presets/.registry sorted ascending by priority; strategy: replace, prepend, append, wrap)
- Tier 3 (Extensions): .specify/extensions/<ext-id>/templates/roadmap-template.md (evaluated per .specify/extensions/.registry sorted ascending by priority)
- Tier 4 (Core Fallback): .specify/templates/roadmap-template.md

Invariant: If a requested template is not found in any of the 4 tiers, the agent MUST fail closed and emit an error per Principle II
-->

**Last Updated**: [YYYY-MM-DD]  
**Governance**: Managed via `/speckit-roadmap` and `.specify/memory/constitution.md`

This roadmap organizes planned strategic initiatives into sequential, self-contained phases. Each phase is designed to be audited (`/speckit-roadmap --status`), specified (`/speckit-roadmap --next` or `/speckit-specify`), planned (`/speckit-plan`), and implemented (`/speckit-implement` / `/speckit-orchestrate`) with full traceability to `specs/NNN-*/`.

---

## Overview of Initiatives

| Phase | Initiative | Status | Prerequisites | Spec | Goal | Key Deliverables |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Phase 1** | **[Phase 1 Title]** | `PLANNED` | None | — | [One-sentence goal] | [Comma-separated key deliverables] |
| **Phase 2** | **[Phase 2 Title]** | `PLANNED` | Phase 1 | — | [One-sentence goal] | [Comma-separated key deliverables] |

<!--
Overview Table Invariants:
1. Phase: Bold sequential identifier `**Phase N**` (`N >= 1`).
2. Initiative: Bold concise phase title `**<Title>**`.
3. Status: Backtick-wrapped status token from closed enum: `PLANNED`, `IN_PROGRESS`, `COMPLETED`, `DEFERRED`.
4. Prerequisites: `None` or comma-separated upstream phase identifiers (`Phase 1`, `Phase 1, Phase 2`). Earlier phases only (M < N).
5. Spec: Backtick-wrapped relative path to feature spec folder (e.g., `specs/001-feature/`) or em-dash `—` when unassigned.
6. Goal: Concise strategic objective statement.
7. Key Deliverables: Summary of artifacts produced by the phase.
-->

---

## Phase 1: [Phase 1 Title]

### Metadata
- **Status**: `PLANNED`
- **Prerequisites**: None
- **Spec Directory**: —

### Problem Statement
[Numbered or bulleted explanation of the problem, gap, and strategic motivation]

### Architectural Fit in Spec Kit
<!-- Note: "Architectural Fit & Scope" is also accepted as a valid secondary heading alias -->
[How the phase integrates with Spec Kit architecture, templates, skills, presets, extensions, and governance]

### Key Deliverables
- [Deliverable 1]
- [Deliverable 2]

### Key Design Decisions to Resolve During Spec
- **[Decision Topic 1]**: [Description of trade-offs or options]
- **[Decision Topic 2]**: [Description of trade-offs or options]

---

## Phase 2: [Phase 2 Title]

### Metadata
- **Status**: `PLANNED`
- **Prerequisites**: Phase 1
- **Spec Directory**: —

### Problem Statement
[Numbered or bulleted explanation of the problem, gap, and strategic motivation]

### Architectural Fit in Spec Kit
<!-- Note: "Architectural Fit & Scope" is also accepted as a valid secondary heading alias -->
[How the phase integrates with Spec Kit architecture, templates, skills, presets, extensions, and governance]

### Key Deliverables
- [Deliverable 1]
- [Deliverable 2]

### Key Design Decisions to Resolve During Spec
- **[Decision Topic 1]**: [Description of trade-offs or options]
- **[Decision Topic 2]**: [Description of trade-offs or options]
