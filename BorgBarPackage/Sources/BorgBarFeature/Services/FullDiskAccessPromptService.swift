import Foundation
import AppKit

@MainActor
public final class FullDiskAccessPromptService {
    private var didPromptForFullDiskAccess = false

    public init() {}

    public func promptIfNeeded(openSystemSettings: @escaping @MainActor () -> Void) async {
        guard !didPromptForFullDiskAccess else { return }
        didPromptForFullDiskAccess = true

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Full Disk Access Required"
        alert.informativeText = "BorgBar needs Full Disk Access to read protected files from snapshots. Grant access now to avoid backup failures."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openSystemSettings()
        }
    }
}
