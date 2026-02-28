import Foundation

public enum HelperHealthStatus: Sendable {
    case healthy
    case notInstalled
    case unhealthy(String)
}

public actor HelperInstallerService {
    private let runner: CommandRunner
    private let fileManager: FileManager
    private let helperPath: String

    public init(
        runner: CommandRunner = CommandRunner(),
        fileManager: FileManager = .default,
        helperPath: String = "/usr/local/libexec/borgbar-helper"
    ) {
        self.runner = runner
        self.fileManager = fileManager
        self.helperPath = helperPath
    }

    public func isInstalled() -> Bool {
        fileManager.isExecutableFile(atPath: helperPath)
    }

    public func healthStatus() -> HelperHealthStatus {
        guard isInstalled() else {
            return .notInstalled
        }

        do {
            let tmutilResult = try runner.run(
                executable: helperPath,
                arguments: ["/usr/bin/tmutil", "listlocalsnapshotdates"],
                timeoutSeconds: 30
            )
            guard tmutilResult.exitCode == 0 else {
                let detail = (tmutilResult.stderr.isEmpty ? tmutilResult.stdout : tmutilResult.stderr)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if indicatesOutdatedHelper(detail) {
                    return .unhealthy("Privileged helper is outdated. Open Settings and click Install Helper.")
                }
                return .unhealthy("Privileged helper check failed: \(detail)")
            }

            let pmsetResult = try runner.run(
                executable: helperPath,
                arguments: ["/usr/bin/pmset", "-g", "sched"],
                timeoutSeconds: 30
            )
            guard pmsetResult.exitCode == 0 else {
                let detail = (pmsetResult.stderr.isEmpty ? pmsetResult.stdout : pmsetResult.stderr)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if indicatesOutdatedHelper(detail) {
                    return .unhealthy("Privileged helper is outdated. Open Settings and click Install Helper.")
                }
                return .unhealthy("Privileged helper check failed: \(detail)")
            }

            return .healthy
        } catch {
            return .unhealthy("Privileged helper check failed: \(error.localizedDescription)")
        }
    }

    public func install() throws {
        AppLogger.info("Helper install requested")
        let temporaryScript = fileManager.temporaryDirectory
            .appendingPathComponent("borgbar-install-helper-\(UUID().uuidString).sh")
        let script = embeddedInstallScript()
        try script.write(to: temporaryScript, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: temporaryScript.path)
        defer { try? fileManager.removeItem(at: temporaryScript) }

        let command = "/bin/zsh \(shellEscape(temporaryScript.path))"
        let osa = "do shell script \"\(escapeAppleScriptString(command))\" with administrator privileges"
        let result = try runner.run(executable: "/usr/bin/osascript", arguments: ["-e", osa], timeoutSeconds: 300)
        guard result.exitCode == 0 else {
            AppLogger.error("Helper install failed: \(result.stderr.isEmpty ? result.stdout : result.stderr)")
            throw BackupError.snapshotFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        AppLogger.info("Helper install completed")
    }

    private func escapeAppleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func indicatesOutdatedHelper(_ detail: String) -> Bool {
        let lower = detail.lowercased()
        return lower.contains("arguments not allowed") || lower.contains("executable not allowed")
    }

    private func shellEscape(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private func embeddedInstallScript() -> String {
        """
        #!/bin/zsh
        set -euo pipefail

        if [[ $EUID -ne 0 ]]; then
          echo "This script must run as root"
          exit 1
        fi

        INSTALL_DIR="/usr/local/libexec"
        HELPER_PATH="$INSTALL_DIR/borgbar-helper"
        SRC_PATH="/tmp/borgbar-helper.c"

        mkdir -p "$INSTALL_DIR"

        cat > "$SRC_PATH" <<'C_EOF'
        #include <stdio.h>
        #include <stdlib.h>
        #include <string.h>
        #include <unistd.h>
        #include <ctype.h>

        static int starts_with(const char *s, const char *prefix) {
            return strncmp(s, prefix, strlen(prefix)) == 0;
        }

        static int is_valid_schedule_datetime(const char *s) {
            if (!s || strlen(s) != 17) {
                return 0;
            }
            if (s[2] != '/' || s[5] != '/' || s[8] != ' ' || s[11] != ':' || s[14] != ':') {
                return 0;
            }
            if (!isdigit((unsigned char)s[0]) || !isdigit((unsigned char)s[1]) ||
                !isdigit((unsigned char)s[3]) || !isdigit((unsigned char)s[4]) ||
                !isdigit((unsigned char)s[6]) || !isdigit((unsigned char)s[7]) ||
                !isdigit((unsigned char)s[9]) || !isdigit((unsigned char)s[10]) ||
                !isdigit((unsigned char)s[12]) || !isdigit((unsigned char)s[13]) ||
                !isdigit((unsigned char)s[15]) || !isdigit((unsigned char)s[16])) {
                return 0;
            }

            int month = (s[0] - '0') * 10 + (s[1] - '0');
            int day = (s[3] - '0') * 10 + (s[4] - '0');
            int hh = (s[9] - '0') * 10 + (s[10] - '0');
            int mm = (s[12] - '0') * 10 + (s[13] - '0');
            int ss = (s[15] - '0') * 10 + (s[16] - '0');
            return month >= 1 && month <= 12 &&
                   day >= 1 && day <= 31 &&
                   hh >= 0 && hh <= 23 &&
                   mm >= 0 && mm <= 59 &&
                   ss >= 0 && ss <= 59;
        }

        int main(int argc, char *argv[]) {
            if (argc < 2) {
                fprintf(stderr, "usage: borgbar-helper <executable> [args...]\\n");
                return 2;
            }

            const char *exe = argv[1];

            if (strcmp(exe, "/usr/bin/tmutil") == 0) {
                if (argc >= 3 && strcmp(argv[2], "localsnapshot") == 0) {
                    execv(exe, &argv[1]);
                    perror("execv tmutil localsnapshot");
                    return 1;
                }
                if (argc >= 3 && strcmp(argv[2], "listlocalsnapshotdates") == 0) {
                    execv(exe, &argv[1]);
                    perror("execv tmutil listlocalsnapshotdates");
                    return 1;
                }
                if (argc >= 4 && strcmp(argv[2], "deletelocalsnapshots") == 0 && starts_with(argv[3], "20")) {
                    execv(exe, &argv[1]);
                    perror("execv tmutil deletelocalsnapshots");
                    return 1;
                }
                fprintf(stderr, "tmutil arguments not allowed\\n");
                return 3;
            }

            if (strcmp(exe, "/sbin/mount_apfs") == 0) {
                if (argc >= 6) {
                    execv(exe, &argv[1]);
                    perror("execv mount_apfs");
                    return 1;
                }
                fprintf(stderr, "mount_apfs arguments not allowed\\n");
                return 3;
            }

            if (strcmp(exe, "/sbin/umount") == 0) {
                if (argc == 3) {
                    execv(exe, &argv[1]);
                    perror("execv umount");
                    return 1;
                }
                fprintf(stderr, "umount arguments not allowed\\n");
                return 3;
            }

            if (strcmp(exe, "/usr/bin/pmset") == 0) {
                if (argc == 4 && strcmp(argv[2], "-g") == 0 && strcmp(argv[3], "sched") == 0) {
                    execv(exe, &argv[1]);
                    perror("execv pmset -g sched");
                    return 1;
                }
                if (argc == 4 && strcmp(argv[2], "repeat") == 0 && strcmp(argv[3], "cancel") == 0) {
                    execv(exe, &argv[1]);
                    perror("execv pmset repeat cancel");
                    return 1;
                }
                if (argc == 4 &&
                    strcmp(argv[2], "schedule") == 0 &&
                    strcmp(argv[3], "cancel") == 0) {
                    execv(exe, &argv[1]);
                    perror("execv pmset schedule cancel");
                    return 1;
                }
                if (argc == 5 &&
                    strcmp(argv[2], "schedule") == 0 &&
                    strcmp(argv[3], "wakeorpoweron") == 0 &&
                    is_valid_schedule_datetime(argv[4])) {
                    execv(exe, &argv[1]);
                    perror("execv pmset schedule wakeorpoweron");
                    return 1;
                }
                fprintf(stderr, "pmset arguments not allowed\\n");
                return 3;
            }

            fprintf(stderr, "executable not allowed: %s\\n", exe);
            return 3;
        }
        C_EOF

        cc "$SRC_PATH" -O2 -o "$HELPER_PATH"
        chown root:wheel "$HELPER_PATH"
        chmod 4755 "$HELPER_PATH"
        rm -f "$SRC_PATH"
        echo "Installed privileged helper at $HELPER_PATH"
        """
    }
}
