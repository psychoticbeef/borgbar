# Backlog (Derived from plan.md)

## Milestone 0

- M0-1 Menubar app skeleton with popover
- M0-2 Core module layout and logging bootstrap
- M0-3 App support/log directory bootstrap

## Milestone 1

- M1-1 Config model + persistence service
- M1-2 Config validator + startup validation UI
- M1-3 Setup UI (single repo)
- M1-4 Keychain service for repo passphrase
- M1-5 Preflight checks (`borg`, SSH key, keychain)

## Milestone 2

- M2-1 Privileged helper target + `SMJobBless` install flow
- M2-2 XPC contract and client/server stubs
- M2-3 Helper signature validation
- M2-4 Snapshot create/mount/unmount/delete implementation
- M2-5 Stale snapshot cleanup on startup

## Milestone 3

- M3-1 Orchestrator state machine + transition logging
- M3-2 Single active run lock
- M3-3 Cancel path (TERM/KILL + cleanup)
- M3-4 Persist terminal run states

## Milestone 4

- M4-1 Borg process runner abstraction
- M4-2 `create -> prune -> compact` execution
- M4-3 Output parsing + phase mapping
- M4-4 Retry policy + one-time break-lock

## Milestone 5

- M5-1 Menubar state mapping
- M5-2 Popover idle/running/error views
- M5-3 Back Up Now / Stop / Open Logs / Try Again
- M5-4 Last-run summary rendering

## Milestone 6

- M6-1 Daily scheduler
- M6-2 Missed-run catch-up
- M6-3 Scheduler guard against concurrent runs
- M6-4 Schedule settings UI

## Milestone 7

- M7-1 Notification service
- M7-2 `history.json` model + rolling retention
- M7-3 Per-run log correlation and rotation

## Milestone 8 (Optional)

- M8-1 Wake toggle + settings
- M8-2 Daily wake registration
- M8-3 AC power gating

