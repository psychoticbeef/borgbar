# Agentic Delivery Loop (BorgBar)

This defines how implementation is executed as a multi-role team with strict reviewer gates.

## Team Roles

- **Product Owner (PO)**
  - Maintains scope against `prd.md` and `plan.md`.
  - Accepts/rejects milestone completion.

- **Implementer**
  - Delivers code for a single ticket slice.
  - Must include tests and local validation notes.

- **Reviewer 1 (Correctness)**
  - Finds logic bugs, race conditions, cleanup failures, state machine gaps.

- **Reviewer 2 (Reliability/Security)**
  - Focuses on privileged helper boundary, subprocess safety, keychain/secret handling.

- **Integrator**
  - Resolves review findings.
  - Produces final milestone summary.

## Loop Cadence

One loop = one small deliverable (usually 1-3 days worth of work).

1. **Plan Slice**
   - Pick exactly one scoped ticket from `docs/process/backlog.md`.
   - Define done criteria and test matrix for that slice.

2. **Implement**
   - Build only the selected slice.
   - Add/update tests.
   - Record design decisions in commit notes.

3. **Self-Check Gate**
   - Build passes.
   - Tests pass (or explicitly documented gap).
   - No secrets in logs/config.

4. **Reviewer Passes (Mandatory)**
   - Reviewer 1 produces findings list (severity ordered).
   - Reviewer 2 produces findings list (severity ordered).
   - Zero unresolved P0/P1 findings allowed to proceed.

5. **Fix + Re-Review**
   - Integrator addresses findings.
   - Reviewers confirm closure.

6. **Milestone Update**
   - Update status board in `docs/process/status.md`.
   - PO marks slice done or returns for rework.

## Review Severity Policy

- **P0**: data loss, corruption, privilege escalation, broken cleanup
- **P1**: incorrect behavior likely in normal use
- **P2**: edge-case bug or observability gap
- **P3**: non-blocking improvements

Release gate for each slice: no open P0/P1.

## Definition of Done (Per Slice)

A slice is done only if all are true:

- Acceptance criteria from `plan.md` for that slice are met.
- Tests relevant to the slice exist and pass.
- Reviewer 1 and Reviewer 2 sign off (no open P0/P1).
- `docs/process/status.md` updated with evidence.

## Non-Negotiables for BorgBar

- APFS snapshot lifecycle must be leak-free on failures/cancel.
- App never edits `~/.ssh/config`.
- No `borgmatic` dependency.
- Secrets only in Keychain.

