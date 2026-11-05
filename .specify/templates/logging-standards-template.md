# [PROJECT_NAME] Logging Standards

<!--
Template Resolution Hierarchy Specification:
This template is resolved by agent skills using the native 4-tier template resolution hierarchy:
- Tier 1 (Overrides): .specify/templates/overrides/logging-standards-template.md
- Tier 2 (Presets): .specify/presets/<preset-id>/templates/logging-standards-template.md (evaluated per .specify/presets/.registry sorted ascending by priority; strategy: replace, prepend, append, wrap)
- Tier 3 (Extensions): .specify/extensions/<ext-id>/templates/logging-standards-template.md (evaluated per .specify/extensions/.registry sorted ascending by priority)
- Tier 4 (Core Fallback): .specify/templates/logging-standards-template.md

Invariant: If a requested template is not found in any of the 4 tiers, the agent MUST fail closed and emit an error per Principle II.
-->

## Constitutional Authority & Precedence

This document operationalizes the telemetry, logging, and observability principles established in the **[PROJECT_NAME] Constitution** into concrete operational standards.

- **Authority Link**: Governed by the rules and principles defined in `.specify/memory/constitution.md` (or `constitution.md`), specifically Principle II (*Two-Tier Failure Model & Fail Closed on Required State*) and Principle VII (*Code Hygiene, Ubiquitous Language & Safe Logging*).
- **Precedence Declaration**: The Constitution ranks highest in authority. In any conflict between this Logging Standards document and the Core Principles of the Constitution, the Constitution strictly prevails.
- **Scope**: Applies to all production services, background workers, command-line interfaces, libraries, and diagnostic telemetry sinks across this repository.

---

## Severity Taxonomy

Telemetric event logging divides into four core severity levels mapped to the Two-Tier Failure Model, plus an optional fifth level (`TRACE`) for mechanical function tracing:

- **CRITICAL** — System restarting or halting immediately. Fatal defect invariants, violated preconditions, unrecoverable programmer errors, or corrupted internal state. MUST include exception details and restart reason.
- **WARN** — Recoverable operation rejection or failure where execution continues. Worth monitoring for patterns in production; declined or failed operations MUST NOT be hidden in DEBUG.
- **INFO** — Significant lifecycle milestone. States the business or system outcome rather than internal diagnostic data; should read like an audit trail. Significant actions MUST log both attempt and result so mid-operation crashes leave a record.
- **DEBUG** — Application's interpretation of state and diagnostic reasoning prior to a milestone ("engineer's working notes"). Carries internal diagnostic reasoning; MUST NOT leak into INFO.
- **TRACE (Optional)** — Mechanical entry and exit logging on every function and return path with parameter and return values, when enabled by the project.

---

## Level Placement & Logging Mechanics

1. **Outcome vs. Diagnostic Reasoning**:
   - `INFO` states what happened (e.g., `"Payment held for review"`). `DEBUG` carries the diagnostic reasoning (e.g., `"FraudScore=0.87 exceeds threshold=0.75"`). Never put diagnostic data in `INFO`.
2. **Attempt and Result Logging**:
   - Significant actions being taken (not just final outcomes) belong at `INFO` — log both the attempt and the result so that a crash mid-operation leaves a verifiable forensic record.
3. **Failures and Rejections**:
   - Declined, rejected, or failed-but-continuing operations MUST be logged at `WARN`, never hidden in `DEBUG`.
4. **Lifecycle Actions in Verbose Layers**:
   - An internal engine, driver, or backend module behind a higher-level entry point still logs its one-time startup, initialization, and shutdown actions at `INFO` if the action executes once per lifecycle and its effect persists for the entire lifecycle. The verbose default for such layers applies only to recurring, per-event work.
5. **No Redundant Callee Logging (When TRACE Is Enabled)**:
   - Do not re-log what a callee's `TRACE` already shows. If data is significant enough for `DEBUG`, prefer promoting that `TRACE` line to `DEBUG` over adding duplicate lines.

---

## TRACE Entry & Exit Rules (Optional)

*Applies only when mechanical `TRACE`-level function tracing is enabled for this project.*

1. **Comprehensive Coverage**:
   - Mechanical entry and exit logging on every function and every return path.
   - An exit `TRACE` is required even when an `INFO` or `WARN` immediately precedes the return statement.
2. **Complex Object Representation**:
   - For complex object parameters, use a `ToString` override or a dedicated `ToTrace` helper with a fixed set of cheap properties. Do not select or extract arbitrary fields inline at each call site.
3. **External Library Seam**:
   - External library calls have no `TRACE`. Log what was returned or observed at `DEBUG` in the caller instead.

---

## Ambient Scope Correlation & Context

1. **Scope-Driven Correlation Tokens**:
   - `session_id` and `event_id` MUST be read from ambient scope state automatically.
   - NEVER pass correlation IDs as method arguments or log them manually at call sites.
2. **Structured Semantic Templates**:
   - All log messages MUST use structured message templates with named placeholders (e.g., `"Order {OrderId} processed for user {UserId}"`).
   - String concatenation, arbitrary string formatting, and raw string interpolation that obliterate property semantics are prohibited.

---

## Forbidden Data & Redaction Policy

1. **Strictly Forbidden Data**:
   - Passwords, tokens, secrets, API keys, authentication credentials, and cryptographic private keys MUST NEVER appear in logs or operator-visible outputs.
   - Full credit card numbers, SSNs, government identification numbers, or raw PII (Personally Identifiable Information) MUST NEVER be logged.
2. **Permitted Identifiers**:
   - Non-sensitive internal domain entity identifiers (such as GUIDs, database row IDs, order numbers, and usernames) are permitted.

---

## Performance & Testing Boundary Rules

1. **Performance Level Guards**:
   - Guard expensive log argument evaluations or string serializations with an explicit level check (e.g., checking if `DEBUG` is enabled). Simple variable interpolation does not require a guard.
   - High-frequency events (sustained >100/sec) MUST be sampled or aggregated rather than logging every individual occurrence.
2. **Testing Boundary Rule**:
   - Unit tests MUST NOT assert on log message text, log formats, or operator display strings. Tests verify domain outcomes and state contracts.

---

## Project Telemetry Configuration

This section specifies project-specific telemetry libraries, sinks, formats, and retention rules for **[PROJECT_NAME]**.

### Logging Framework & Abstraction
- **Framework**: [LOGGING_FRAMEWORK]
  <!-- Example: Serilog with Microsoft.Extensions.Logging, or Winston, or log4rs -->

### Sinks, Destinations & Output Formats
- **Sinks & Formats**: [LOG_SINKS_AND_FORMATS]
  <!-- Example: Console (Compact JSON format) + OpenTelemetry Collector OTLP exporter -->

### Correlation Identifier Schema
- **Correlation Schema**: [CORRELATION_ID_SCHEMA]
  <!-- Example: W3C TraceContext traceparent, session_id (UUIDv4), event_id (monotonic int) -->

### Redaction & Sanitization Mechanism
- **Redaction Engine**: [SENSITIVE_DATA_REDACTION_MECHANISM]
  <!-- Example: Middleware redaction regex filter stripping Authorization headers and masking card digits -->

### Retention & High-Frequency Sampling Policy
- **Retention & Sampling**: [RETENTION_AND_SAMPLING_POLICY]
  <!-- Example: Production DEBUG retained 7 days; sustained >100/sec events sampled at 5% -->
