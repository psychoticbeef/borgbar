# BorgBar User Stories (Conversation + Code Consolidation)

## Scope
This file consolidates user stories from:
- Current codebase behavior
- Product direction in `prd.md`
- Thread-level micromanaged decisions and corrections

Primary persona: solo power user running BorgBar for personal backups on macOS.

---

## Epic 1: Product Boundaries, Distribution, and MVP Scope

### US-001 Single-user-first product
As a solo user, I want BorgBar optimized for one-person operation so that I can run reliable backups without team-level complexity.
Acceptance Criteria:
- MVP assumes a single operator and one primary repository.
- Setup and defaults favor local personal usage.
- Multi-tenant or enterprise controls are out of MVP scope.

### US-002 Snapshotting is non-negotiable
As a user, I want every backup to run from an APFS snapshot so that backups are consistent while the system is live.
Acceptance Criteria:
- Backup runs fail if snapshot create or mount fails.
- App never silently falls back to backing up the live filesystem.

### US-003 No borgmatic dependency
As a user, I want BorgBar to orchestrate Borg directly so that I have one control plane and no external wrapper dependency.
Acceptance Criteria:
- No runtime dependency on `borgmatic`.
- Orchestration is performed in app code.

### US-004 Distribution outside App Store
As a user, I want direct distribution so that privileged operations are feasible.
Acceptance Criteria:
- Distribution target is GitHub Releases.
- App Store constraints are not used to define architecture.

### US-005 Signed release path
As a user, I want signed releases so that security prompts and trust are sane.
Acceptance Criteria:
- Local/dev builds may precede full release signing process.
- Release process includes signing expectations.

### US-006 No `~/.ssh/config` edits ever
As a user, I want strict non-interference with my SSH config so that backup tooling never mutates global SSH behavior.
Acceptance Criteria:
- App must not read/write/append `~/.ssh/config` for configuration management.
- This remains true post-MVP.

### US-007 JSON config as source of truth
As a user, I want app settings stored in JSON so that behavior is transparent and debuggable.
Acceptance Criteria:
- Config is persisted in app support JSON.
- Settings edits round-trip through JSON without hidden stores.

### US-008 Restores out of MVP
As a user, I want MVP focused on reliable backup creation so that delivery scope stays realistic.
Acceptance Criteria:
- In-app restore browsing is deferred.
- Existing Borg CLI restore remains supported path.

### US-009 No unnecessary backward compatibility burden
As a user, I want schema and UX to prioritize correctness over legacy baggage so that fixes can be applied quickly.
Acceptance Criteria:
- Migration support is limited to required safety paths.
- New exclusion model remains authoritative.

### US-010 Reviewer-gated delivery
As a user, I want reviewer-heavy delivery loops so that reliability and security regressions are caught early.
Acceptance Criteria:
- Correctness and reliability/security review passes are explicit.
- P0/P1 findings block acceptance.

---

## Epic 2: Privileged Operations and Permission UX

### US-011 One-time privilege model
As a user, I want to grant privilege once so that I am not repeatedly prompted for admin password.
Acceptance Criteria:
- Privileged helper installation is one-time.
- Normal backup runs do not trigger repeated password prompts.

### US-012 In-app helper install flow
As a user, I want the app to guide helper installation so that I do not need manual shell/script steps.
Acceptance Criteria:
- App provides install action from Settings.
- Missing helper errors provide direct install guidance.

### US-013 Proactive helper health on startup
As a user, I want helper status checked at launch so that I am warned before starting a backup.
Acceptance Criteria:
- App checks helper health during startup.
- Outdated/missing helper is surfaced immediately.

### US-014 Helper outdated detection
As a user, I want explicit helper-outdated messaging so that remediation is obvious.
Acceptance Criteria:
- Outdated helper is distinguished from missing helper.
- Message includes direct action to reinstall helper.

### US-015 Strict helper command boundary
As a user, I want helper operations constrained to snapshot lifecycle so that privilege scope stays minimal.
Acceptance Criteria:
- Helper is used only for snapshot-related commands.
- No network/Borg/keychain logic in helper path.

### US-016 Full Disk Access precondition
As a user, I want FDA checked before protected operations so that I avoid cascaded failures.
Acceptance Criteria:
- FDA check runs during startup.
- App surfaces FDA-required status before backup/snapshot mount failure.

### US-017 FDA prompt with deep link
As a user, I want one-click navigation to the correct macOS settings pane so that permission recovery is fast.
Acceptance Criteria:
- App can open Privacy & Security settings location.
- Prompt text explains why FDA is needed.

### US-018 FDA diagnostics
As a user, I want probe-level diagnostics so that I can see exactly what is blocked.
Acceptance Criteria:
- UI surfaces denied/error probe lines.
- Logs include first failing probe context.

### US-019 FDA status consistency across UI surfaces
As a user, I want settings and menubar status to agree so that I can trust app state.
Acceptance Criteria:
- Menubar and settings reflect same FDA truth.
- Re-check action refreshes shared status.

### US-020 Conservative FDA detection
As a user, I want no false “FDA granted” state so that mount errors are prevented.
Acceptance Criteria:
- `tmutil` success alone is not treated as definitive FDA grant.
- Protected path access probes drive final grant decision.

---

## Epic 3: Snapshot Lifecycle, Reuse, and Recovery

### US-021 Snapshot create/mount/delete lifecycle
As a user, I want full snapshot lifecycle automation so that I never run manual mount/delete commands.
Acceptance Criteria:
- Create, mount, cleanup are orchestrated per run.
- On failure/cancel, cleanup means unmount + mountpoint cleanup while preserving the local snapshot for retry/reuse.
- On success, local snapshot deletion follows reuse policy.

### US-022 Snapshot mount failure classification
As a user, I want actionable mount failure messages so that I can recover quickly.
Acceptance Criteria:
- `operation not permitted` maps to FDA remediation guidance.
- `resource busy` maps to retry/reboot guidance.

### US-023 Retry transient snapshot mount errors
As a user, I want automatic retries on transient mount errors so that temporary APFS contention does not fail runs.
Acceptance Criteria:
- Mount retries on known transient signatures.
- Retry window is bounded.

### US-024 Snapshot reuse until next scheduled backup
As a user, I want snapshot reuse to continue until the next scheduled backup boundary so retries and restarts do not create unnecessary snapshots.
Acceptance Criteria:
- Reuse state tracks a cutoff at the next scheduled backup time.
- Reuse is only attempted when snapshot still exists.

### US-025 Preserve reusable snapshot after failure
As a user, I want failed runs to preserve reusable snapshots until the scheduled cutoff so retries can continue from the same point-in-time source.
Acceptance Criteria:
- Snapshot is not deleted on failed/cancelled runs.
- Reuse state is cleared when stale/missing.

### US-026 Stale mount cleanup on startup
As a user, I want startup cleanup to follow the exact same retention policy as normal runs so snapshot lifecycle is consistent.
Acceptance Criteria:
- `/tmp/borgbar-snapshot-*` cleanup is attempted on launch.
- Unmount + directory removal are best-effort.
- Local snapshot deletion happens only when the retry window reaches the next scheduled backup boundary.

### US-027 No silent fallback away from snapshot source
As a user, I want explicit failure when snapshot source is unavailable so that integrity is never ambiguous.
Acceptance Criteria:
- Backup cannot proceed when snapshot mount is unavailable.

### US-028 Do not restart app behind my back
As a user, I want explicit control over app restarts so that running backup context is respected.
Acceptance Criteria:
- Operational tooling should avoid surprise restarts during active work.
- If restart is needed, reason is communicated.

---

## Epic 4: Borg Pipeline, Progress, and Run Semantics

### US-029 Preflight validation before every run
As a user, I want strict preflight checks so that avoidable failures are caught early.
Acceptance Criteria:
- Validate borg binary path.
- Validate SSH key path.
- Validate keychain passphrase presence.

### US-030 Reachability retry window
As a user, I want network reachability retried for at least one minute so that short outages don’t immediately fail runs.
Acceptance Criteria:
- Reachability probe retries for ~60s total.
- Status message indicates retry window.

### US-031 Backup phases are explicit
As a user, I want phase-level status (preflight, snapshot, archive, prune, compact, cleanup) so that I understand what the app is doing.
Acceptance Criteria:
- Menubar status transitions through defined phases.
- Logs include phase transitions.

### US-032 Archive creation progress visibility
As a user, I want live archive stats so that long backups are observable.
Acceptance Criteria:
- Show read/written/compressed bytes and file count.
- Show throughput/ETA when available.

### US-033 Repo out metric retained
As a user, I want a simple output metric so that I can track repository growth during a run.
Acceptance Criteria:
- `Repo out` is displayed.
- Deprecated network in/out rate fields are removed.

### US-034 Cache checkpoint status clarity
As a user, I want cache checkpoint phases explained so that “creating archive” doesn’t look like a stall.
Acceptance Criteria:
- Cache checkpoint messages map to user-friendly status lines.
- Log lines retain raw evidence.

### US-035 Borg warnings on create can still be success
As a user, I want non-fatal Borg warning exits handled correctly so completed archives are not misclassified as failed.
Acceptance Criteria:
- Exit code 1 with completed archive markers is treated as success-with-warning path.

### US-036 Lock recovery path
As a user, I want automatic one-time break-lock retry so stale repository locks do not force manual intervention.
Acceptance Criteria:
- On lock failure signature, app attempts `borg break-lock` once then retries create.

### US-037 Prune/compact warning semantics
As a user, I want backup data success distinguished from maintenance failures so I can prioritize response.
Acceptance Criteria:
- Successful create + prune/compact failure => success with warning.
- Run summary captures maintenance warnings.

### US-038 Retry failed backup until next scheduled run
As a user, I want automatic delayed retries on failure so transient faults self-heal before the next scheduled backup cycle.
Acceptance Criteria:
- Failed run schedules retry attempts about every hour.
- Retries stop at the next scheduled backup time.
- Retry schedule is cleared when a new run starts or succeeds.

### US-039 Do not prune incomplete archives
As a user, I want interrupted/failed creates not to trigger normal retention pruning so useful partial data/chunks are preserved.
Acceptance Criteria:
- `prune`/`compact` only run after successful create stage.

### US-040 Cancel behavior must be controlled
As a user, I want cancel to be graceful first and forceful only when needed so repository integrity is preserved.
Acceptance Criteria:
- Cancel path terminates running Borg process.
- Cleanup still runs and outcome is persisted as cancelled.

### US-041 Quit warning while backup active
As a user, I want a quit confirmation when backup is running so I don’t accidentally kill a run.
Acceptance Criteria:
- Quit prompt offers cancel/continue.
- If stopping hangs, second prompt offers force-quit warning.

### US-042 Break-lock on quit shutdown path
As a user, I want optional lock cleanup on app termination so next launch is less likely to hit stale lock issues.
Acceptance Criteria:
- On confirmed quit after stop, app attempts lock cleanup.

### US-043 Resume semantics transparency
As a user, I want the app to clearly explain what “continue” means after interruption so expectations match Borg behavior.
Acceptance Criteria:
- UI/docs distinguish checkpoint/chunk reuse from same-archive continuation.
- App avoids claiming unsupported same-archive continuation semantics.

---

## Epic 5: Exclusions, Backup Scope, and Data Selection

### US-044 Three exclusion layers
As a user, I want exclusion handling split into user list, common-sense list, and TM-derived list so policy is explainable.
Acceptance Criteria:
- Separate storage and UI sections for each list.
- Effective excludes are merged in backup execution.

### US-045 User folder-content exclusion
As a user, I want to exclude folder contents but keep the folder itself so structure remains restorable.
Acceptance Criteria:
- Example: keep `~/Downloads` directory entry while excluding children.

### US-046 User glob exclusion patterns
As a user, I want glob-based exclusions (e.g. `*/venv/*`) so toolchain directories are easy to omit.
Acceptance Criteria:
- Pattern list is persisted and applied to Borg create.

### US-047 Common-sense defaults always on
As a user, I want common junk/cache patterns excluded by default so repository noise is reduced.
Acceptance Criteria:
- Defaults include cache/trash/dev artifacts and similar noise patterns.

### US-048 Time Machine exclusion import on startup
As a user, I want TM exclusions scanned at startup when needed so the app mirrors system backup intent.
Acceptance Criteria:
- Scan runs when OS version changed or not yet scanned.
- Scan does not wait for backup start.

### US-049 TM scan gated by FDA
As a user, I want TM scanning blocked until FDA is granted so I avoid redundant document/music prompts and noisy failures.
Acceptance Criteria:
- If FDA missing, scan is skipped with clear status.

### US-050 Persist TM exclusion scan metadata
As a user, I want scan version/timestamp persisted so rescan behavior is deterministic.
Acceptance Criteria:
- Persist OS version + scanned-at timestamp.

### US-051 Skip exclusions already covered by defaults
As a user, I want TM-derived excludes added only when not already covered by default patterns so exclusion set stays minimal.
Acceptance Criteria:
- Effective TM additions are filtered against common-sense patterns.

### US-052 Prune traversal under excluded branches
As a user, I want exclusion scanning to avoid descending into already-excluded trees (e.g. `~/Library/Logs`) so scans are faster and cleaner.
Acceptance Criteria:
- Scanner detects shallow TM-excluded roots and skips descendants.
- Result may keep root excluded path without child explosion.

### US-053 Chunk failure recovery in TM scan
As a user, I want failed `tmutil` chunks recovered path-by-path so excluded roots are not silently lost.
Acceptance Criteria:
- Failed chunk members get single-path fallback probing.

### US-054 User exclusions must persist reliably
As a user, I want exclusion edits to survive restart so settings are trustworthy.
Acceptance Criteria:
- `userExcludePatterns` and `userExcludeDirectoryContents` persist round-trip.

### US-055 Migration for legacy exclusion keys
As a user, I want legacy config migrated into current exclusion fields so upgrades don’t drop my policy.
Acceptance Criteria:
- Legacy keys are mapped to current fields.

### US-056 Git-ignored artifacts policy
As a user, I want an explicit decision on `.gitignore`-driven exclusions so behavior is predictable.
Acceptance Criteria:
- If implemented, behavior is documented and toggleable.
- If not implemented, rationale is explicit.

### US-057 Backup target scope transparency
As a user, I want to know exactly what folder(s) are included so backup scope is never ambiguous.
Acceptance Criteria:
- Include paths are visible in settings/config.
- Scope can be changed and persisted.

### US-058 Verify sparse-file handling policy
As a user, I want sparse handling defaulted for restore safety with explicit tradeoff communication.
Acceptance Criteria:
- Sparse handling is default-on.
- UI explains dedup tradeoff vs restore correctness.

---

## Epic 6: Menubar and Settings UX

### US-059 Menubar icon must always appear
As a user, I want a reliable status-bar icon so the app is discoverable and controllable.
Acceptance Criteria:
- App launches as accessory menubar app with visible icon.

### US-060 Popover interactivity reliability
As a user, I want popover controls clickable every time so app control is dependable.
Acceptance Criteria:
- Popover receives focus on open.
- No dead/non-clickable state after launch.

### US-061 Back Up Now and Stop actions
As a user, I want immediate run control from menubar so I can intervene quickly.
Acceptance Criteria:
- Back Up Now triggers manual run.
- Stop triggers cancel flow.

### US-062 Quit action in menubar UI
As a user, I want a direct quit button so app lifecycle control is easy.
Acceptance Criteria:
- Quit action is present in menubar popover.

### US-063 Configure passphrase in Settings
As a user, I want passphrase controls in Settings (not scattered in popover actions) so configuration is coherent.
Acceptance Criteria:
- Passphrase save UI is in Settings.

### US-064 Settings layout clarity
As a user, I want neat visual affordances for add/remove exclusion actions so editing feels deliberate.
Acceptance Criteria:
- Add/remove controls are visually distinct and semantically colored.

### US-065 Read-only list sections for defaults and TM
As a user, I want system-derived and built-in exclusion lists clearly separated from editable user lists.
Acceptance Criteria:
- User-editable and read-only sections are separate.

### US-066 Last run summary in popover
As a user, I want last run outcome/time in quick view so I can check health at a glance.
Acceptance Criteria:
- Last run outcome and timestamp are shown.

### US-067 Status messages should explain long phases
As a user, I want meaningful status text during long operations so I can distinguish progress from stalls.
Acceptance Criteria:
- Creating-archive/cache phases provide explanatory text.

### US-068 Open logs from UI
As a user, I want one-click log access from popover/settings so diagnosis is immediate.
Acceptance Criteria:
- Open Logs action opens log directory.

### US-069 Helper update prompt at startup
As a user, I want startup surfacing for helper update requirements so I don’t discover it only after failures.
Acceptance Criteria:
- Startup status warns when helper is outdated/missing.

### US-070 Duplicate app instance prevention
As a user, I want only one effective app instance so status and behavior are not contradictory.
Acceptance Criteria:
- Duplicate running instances with same bundle id are terminated on launch.
- Startup logs include active bundle path for verification.

---

## Epic 7: Logging, Diagnostics, and Observability

### US-071 Structured log file location
As a user, I want a stable log file location so I can inspect runtime state quickly.
Acceptance Criteria:
- App logs write to `~/Library/Logs/BorgBar/app.log`.

### US-072 Log verbosity control
As a user, I want reduced default verbosity after debugging so logs stay useful.
Acceptance Criteria:
- Default level is info.
- Progress spam is throttled/aggregated.

### US-073 Keep critical error visibility
As a user, I want high-signal errors retained even with lower verbosity so root cause is still available.
Acceptance Criteria:
- FDA failures, helper issues, and pipeline failures are clearly logged.

### US-074 Progress parser output model
As a user, I want parsed progress to include bytes/rates/ETA so I can monitor long archive creation.
Acceptance Criteria:
- Parser extracts metrics and optional throughput/ETA tokens.

### US-075 Correlate launch binary path in logs
As a user, I want logs to show the launched bundle path so binary confusion can be diagnosed.
Acceptance Criteria:
- Launch line includes `Bundle.main.bundlePath`.

### US-076 Aggregate TM scan skip logging
As a user, I want summarized unreadable-path reporting so logs are informative but not flooded.
Acceptance Criteria:
- Report counts and limited details, not full per-path spam.

### US-077 Keep “repo out” visible during long backup
As a user, I want one stable growth metric during archive creation so I can trust that data is moving.
Acceptance Criteria:
- Repo out updates from deduplicated bytes.

### US-078 Startup diagnostics for permission mismatch
As a user, I want direct diagnostics when settings and runtime disagree so trust can be restored quickly.
Acceptance Criteria:
- Re-check exposes latest FDA probe results.
- Idle status updates when permissions change.

---

## Epic 8: Scheduling, Power, and Runtime Reliability

### US-079 Daily backup schedule
As a user, I want one daily schedule so backups happen automatically.
Acceptance Criteria:
- Daily HH:mm schedule triggers once per day.

### US-080 Missed-run catch-up behavior
As a user, I want missed backups to run when app becomes eligible so sporadic uptime still produces backups.
Acceptance Criteria:
- If schedule time passed and no successful run today, app triggers scheduled run.

### US-081 Prevent sleep during backup
As a user, I want backups protected from system idle sleep so long runs complete.
Acceptance Criteria:
- Sleep assertion enabled at run start and released at end.

### US-082 Wake scheduling toggle
As a user, I want optional wake scheduling so nightly backups can start even when machine is asleep.
Acceptance Criteria:
- Toggle exists in settings.
- App attempts wake event registration when enabled.

### US-083 Wake scheduling failure transparency
As a user, I want explicit wake scheduling failure logs so I can decide whether to rely on wake.
Acceptance Criteria:
- Failed wake registration includes return code in logs.

### US-084 Single active run guard
As a user, I want no concurrent runs so repository and snapshot state remains safe.
Acceptance Criteria:
- Scheduler/manual triggers are ignored when run already active.

### US-085 Retry policy after failure
As a user, I want automatic retries within a bounded window so temporary outages recover without running forever.
Acceptance Criteria:
- Failure schedules delayed retries (~1h cadence).
- Retry window ends at the next scheduled backup time.
- Retry is canceled/cleared on superseding run transitions.

### US-086 Continue running app while backup active
As a user, I want to keep developing/using the machine while backup runs so workflow is uninterrupted.
Acceptance Criteria:
- App UI remains responsive during long backups.
- Backup orchestration survives normal app interactions.

### US-087 Controlled quit behavior during active run
As a user, I want explicit confirmation and cleanup options when quitting so data integrity and UX are balanced.
Acceptance Criteria:
- Quit prompt appears during active run.
- Force quit path warns about lock risk.

### US-088 Post-restart behavior clarity
As a user, I want deterministic behavior after app restart so I know whether a new run/snapshot will be created.
Acceptance Criteria:
- App documents snapshot reuse-until-scheduled-cutoff policy.
- Triggering backup after restart follows defined reuse semantics.

---

## Epic 9: Secrets, SSH, and Security Constraints

### US-089 Keychain-backed passphrase retrieval
As a user, I want passphrase retrieval from Keychain so secrets are not stored in plaintext config.
Acceptance Criteria:
- Passphrase stored per repo id in keychain.
- Borg receives passphrase via `BORG_PASSCOMMAND`.

### US-090 SSH key-only auth
As a user, I want key-based SSH auth only so security posture remains consistent.
Acceptance Criteria:
- Borg uses `BORG_RSH` with explicit key path and `IdentitiesOnly=yes`.

### US-091 No SSH config mutation
As a user, I want hard guarantees that global SSH config is untouched.
Acceptance Criteria:
- No code path mutates `~/.ssh/config`.

### US-092 Optional dedicated backup key handling strategy
As a user, I want a safe strategy for backup-only keys so unattended operation is possible without weak secret handling.
Acceptance Criteria:
- Documented pattern for passphrase in keychain and unattended use.
- No requirement for repetitive user prompts during normal runs.

### US-093 Privileged boundary minimization
As a user, I want elevated code kept tiny and auditable so risk is bounded.
Acceptance Criteria:
- Helper API stays minimal and command-allowlisted.

### US-094 No secret leakage in logs
As a user, I want logs free of sensitive values so diagnostics are safe to share.
Acceptance Criteria:
- Passphrases/private key data are never emitted to logs.

---

## Epic 10: Data Integrity, Restore Confidence, and Sparse Files

### US-095 Sparse-file restore correctness by default
As a user, I want backups that restore sparse files correctly so reported backup size can still produce valid restores.
Acceptance Criteria:
- Sparse mode defaults on.
- Chunker params are set to fixed-size mode for safer sparse restore behavior.

### US-096 Dedup tradeoff transparency
As a user, I want explicit explanation of sparse-vs-dedup tradeoffs so I can choose knowingly.
Acceptance Criteria:
- Settings text explains tradeoff.
- Toggle is user-controllable.

### US-097 Restore confidence over cosmetic efficiency
As a user, I want backup correctness prioritized over apparent size optimization so recoverability is never compromised.
Acceptance Criteria:
- Integrity-oriented defaults are favored.

---

## Epic 11: Process, Tooling, and Engineering Hygiene

### US-098 Agentic implementation loop
As a product owner, I want iterative agentic loops so app changes are continuously implemented, reviewed, and integrated.
Acceptance Criteria:
- Work proceeds in small slices with validation per slice.

### US-099 Reviewer-first culture
As a product owner, I want reviewers central to each change so regressions are surfaced before acceptance.
Acceptance Criteria:
- Findings are tracked and closed before milestone close.

### US-100 Dead code scanning
As a maintainer, I want periodic dead code scans so maintenance burden stays low.
Acceptance Criteria:
- Periphery scan outputs are reviewed and acted on.

### US-101 Duplicate code scanning
As a maintainer, I want duplicate-code scans so structure stays clean.
Acceptance Criteria:
- `jscpd` reports are generated and reviewed.

### US-102 Class-level responsibility review (IOSP/SOLID intent)
As a maintainer, I want periodic class-by-class responsibility checks so non-adherent design is isolated and corrected.
Acceptance Criteria:
- Review loop identifies non-adherence.
- Follow-up refactors reduce responsibility leakage.

---

## Explicit Conversation Directives Captured

The stories above explicitly capture these thread constraints and corrections:
- Snapshot-first, no fallback.
- No borgmatic.
- No App Store distribution.
- Signed release direction via GitHub.
- Never manage `~/.ssh/config`.
- JSON config authority.
- Wake scheduling considered for MVP and implemented as optional.
- One-time privilege objective, avoid repeated password prompts.
- App-driven helper installation and proactive helper health.
- FDA-first flow, with direct settings path and diagnostics.
- Menubar UX improvements including quit.
- Passphrase configuration in Settings.
- Progress clarity around archive cache/checkpoint phases.
- Keep `Repo out`; remove confusing network-rate indicators.
- Retry reachability for 60s and recurring backup retries (~1h cadence) until the next scheduled backup.
- Prevent sleep during backups.
- Snapshot reuse until next scheduled backup boundary.
- Do not prune partial/incomplete create runs.
- TM exclusions split into user/common-sense/TM-derived.
- TM scan on startup (version-gated), FDA-gated, and de-noised.
- Only add TM exclusions not already covered by defaults.
- Correct persistence of exclusion lists and scan metadata.
- Duplicate-instance guard and launch-path logging.
- Log verbosity reduced after debug phase.
- Reviewer-heavy agentic loop expectations.
