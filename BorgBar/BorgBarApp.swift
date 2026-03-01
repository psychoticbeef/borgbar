import SwiftUI
import AppKit
import BorgBarFeature

@main
struct BorgBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    appDelegate.showSettingsWindow(nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let model = BorgBarModel()
    private let terminationPolicy = AppTerminationPolicy()
    private var terminationInFlight = false
    private var settingsWindow: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = NSApp.setActivationPolicy(.accessory)
        terminateDuplicateInstances()

        let content = ContentView(model: model) { [weak self] in
            self?.presentSettingsWindow()
        }
        popover.contentSize = NSSize(width: 380, height: 520)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: content)
        model.start()

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = statusItem

        if let button = statusItem.button {
            button.title = ""
            button.imagePosition = .imageOnly
            button.toolTip = "BorgBar"
            if let image = NSImage(systemSymbolName: "externaldrive.badge.timemachine", accessibilityDescription: "BorgBar") {
                image.isTemplate = true
                button.image = image
            }
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }

    private func terminateDuplicateInstances() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.da.borgbar")
        for app in running where app.processIdentifier != currentPID {
            let path = app.bundleURL?.path ?? "unknown path"
            AppLogger.info("Terminating duplicate BorgBar instance: pid=\(app.processIdentifier) path=\(path)")
            if !app.terminate() {
                _ = app.forceTerminate()
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        switch terminationPolicy.startDecision(
            terminationInFlight: terminationInFlight,
            backupRunning: model.orchestrator.isRunning
        ) {
        case .terminateNow:
            return .terminateNow
        case .terminateCancel:
            return .terminateCancel
        case .needsUserConfirmation:
            break
        }

        let confirm = NSAlert()
        confirm.alertStyle = .warning
        confirm.messageText = "Backup Is Running"
        confirm.informativeText = "Quitting will stop the active backup. Continue?"
        confirm.addButton(withTitle: "Stop Backup and Quit")
        confirm.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        let response = confirm.runModal()
        guard response == .alertFirstButtonReturn else {
            return .terminateCancel
        }

        terminationInFlight = true
        Task { @MainActor in
            model.orchestrator.cancelRun()
            let stopped = await waitForBackupStop(timeoutSeconds: 12)
            if stopped {
                await model.orchestrator.cleanupRepositoryLockForTermination()
                NSApp.reply(toApplicationShouldTerminate: true)
                return
            }

            let force = NSAlert()
            force.alertStyle = .critical
            force.messageText = "Backup Is Still Stopping"
            force.informativeText = "Stopping is taking longer than expected. Quit anyway? This can leave a stale repository lock."
            force.addButton(withTitle: "Quit Anyway")
            force.addButton(withTitle: "Keep Running")
            NSApp.activate(ignoringOtherApps: true)
            let forceResponse = force.runModal()
            let shouldQuit = terminationPolicy.shouldQuitAfterForceChoice(
                userChoseForceQuit: forceResponse == .alertFirstButtonReturn
            )
            if !shouldQuit {
                terminationInFlight = false
            }
            NSApp.reply(toApplicationShouldTerminate: shouldQuit)
        }

        return .terminateLater
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            Task { @MainActor in
                await model.refreshFullDiskAccessStatusForUI()
            }
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Ensure controls in the popover receive mouse/keyboard focus immediately.
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc func showSettingsWindow(_ sender: Any?) {
        _ = sender
        presentSettingsWindow()
    }

    private func presentSettingsWindow() {
        let window: NSWindow
        if let existing = settingsWindow {
            window = existing
        } else {
            let rootView = SettingsView(orchestrator: model.orchestrator)
            let hosting = NSHostingController(rootView: rootView)
            let created = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            created.title = "BorgBar Settings"
            created.contentViewController = hosting
            created.isReleasedWhenClosed = false
            created.center()
            settingsWindow = created
            window = created
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        _ = NSApp.setActivationPolicy(.accessory)
    }

    @MainActor
    private func waitForBackupStop(timeoutSeconds: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while model.orchestrator.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return !model.orchestrator.isRunning
    }
}
