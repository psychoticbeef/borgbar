# Privileged Helper Setup

BorgBar snapshot operations require root privileges.

This project uses a signed privileged helper daemon (`com.da.borgbar.helper`)
managed through `SMAppService` from inside the app.

## Install (one-time)

Use the app UI:
1. Open `Settings`
2. Go to `Security`
3. Click `Install Helper`

## Notes

- Helper service label: `com.da.borgbar.helper`
- Bundled daemon plist: `PrivilegedHelper/com.da.borgbar.helper.plist`
- Helper executable is embedded under app bundle `Contents/Library/HelperTools`
- Allowed commands are restricted to snapshot lifecycle operations plus wake
  scheduling (`tmutil`, `mount_apfs`, `umount`, constrained `pmset`).
- BorgBar will fail with an explicit error if helper is missing/unregistered.
