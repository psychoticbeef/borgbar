# Privileged Helper Setup

BorgBar snapshot operations require root privileges.

This project uses a small setuid-root helper binary that is installed once, then reused without repeated password prompts.

## Install (one-time)

```bash
cd /Users/da/code/BorgBar
sudo ./scripts/install_privileged_helper.sh
```

## Uninstall

```bash
cd /Users/da/code/BorgBar
sudo ./scripts/uninstall_privileged_helper.sh
```

## Notes

- Helper path: `/usr/local/libexec/borgbar-helper`
- Allowed commands are restricted to snapshot lifecycle operations plus wake scheduling (`tmutil`, `mount_apfs`, `umount`, constrained `pmset`).
- BorgBar will fail with an explicit error if helper is missing.
