// SPDX-License-Identifier: MIT
import SwiftUI

@main
struct NotchShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("NotchShot", systemImage: "viewfinder") {
            Button("Capture app  \(delegate.store.captureHintLabel)") { delegate.store.captureFrontmost() }
            Button("Capture shortcut…") { delegate.store.showCaptureSettings() }
            Button("Show / hide notch") { delegate.store.toggleExpanded() }
            if delegate.history.isEnabled {
                Button("Shot history…") { delegate.store.showHistory() }
            }
            Toggle("Both Shift keys to capture", isOn: Binding(
                get: { delegate.store.bothShiftEnabled },
                set: { delegate.store.bothShiftEnabled = $0 }
            ))
            Toggle("Capture sound", isOn: Binding(
                get: { delegate.store.captureSoundEnabled },
                set: { delegate.store.captureSoundEnabled = $0 }
            ))
            Divider()
            Button("Accessibility settings…") { PermissionService.openAccessibilitySettings() }
            Button("Screen recording settings…") { PermissionService.openScreenRecordingSettings() }
            Button("Refresh permissions") { delegate.store.refreshPermissions() }
            Button("Reopen after permission change") { delegate.store.reopenForPermissions() }
            Divider()
            Button("Check for updates…") {
                delegate.store.showCaptureSettings()
                delegate.updates.checkNow()
            }
            .disabled(!delegate.updates.isAvailable || delegate.updates.isBusy)
            Divider()
            Button("Clear session captures") { delegate.store.clearHistory() }.disabled(delegate.store.captures.isEmpty)
            Button("Quit NotchShot") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let history = ShotHistory(preferences: .standard, archive: ShotArchive(root: ShotArchive.defaultRoot()))
    let store: CaptureStore
    let updates = UpdateController.forRunningApp(preferences: .standard)
    private var panelController: NotchPanelController?
    private let shortcut = GlobalShortcutService()
    private let bothShift = BothShiftShortcutService()
    private var cardController: CaptureCardController?

    override init() {
        store = CaptureStore(preferences: .standard, clipboard: .general, history: history)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Deliberate accessory utility: lives in the notch and menu bar, with no Dock icon.
        NSApp.setActivationPolicy(.accessory)
        // Loaded before the store starts so the previous shelf can come back.
        history.load()
        store.start()
        panelController = NotchPanelController(store: store, updates: updates)
        panelController?.show()
        cardController = CaptureCardController(store: store, compactLandingFrame: { [weak self] in
            self?.panelController?.compactLandingFrame
        })
        store.onPresentCard = { [weak self] capture in self?.cardController?.present(capture) }
        store.onDismissCard = { [weak self] in self?.cardController?.dismiss() }
        store.onLandCard = { [weak self] finish in
            guard let card = self?.cardController else { finish(); return }
            card.landInShelf(completion: finish)
        }
        bothShift.onTrigger = { [weak self] in self?.store.captureFrontmost() }
        store.onShortcutSettingsChanged = { [weak self] in self?.configureBothShift() }
        configureBothShift()
        shortcut.onCapture = { [weak self] in self?.store.captureFrontmost() }
        store.onRegisterShortcut = { [weak self] candidate in
            guard let self else { return .failure(-50) }
            let result = self.shortcut.register(shortcut: candidate)
            self.store.shortcutAvailable = self.shortcut.registeredShortcut != nil
            return result
        }
        store.onShortcutRecordingChanged = { [weak self] recording in
            guard let self else { return }
            if recording {
                self.shortcut.unregister()
                self.configureBothShift()
            } else {
                self.configureCaptureShortcut()
                self.configureBothShift()
            }
        }
        configureCaptureShortcut()
        store.onReopen = { [weak self] in self?.relaunch() }
        updates.canInstallNow = { [weak self] in self?.store.canRelaunchUnnoticed ?? false }
        updates.onRelaunch = { [weak self] in self?.relaunch() }
        updates.onNotice = { [weak self] kind, title, message in self?.store.report(kind, title, message: message) }
        updates.start()
    }

    private func relaunch() {
        Task { @MainActor in
            // The next instance reads history at launch, so queued saves land first.
            await history.settle(timeout: .seconds(3))
            performRelaunch()
        }
    }

    private func performRelaunch() {
        // Reopening already clears the shelf, so a waiting update goes in first.
        updates.installPendingUpdate()
        // Release the global shortcut before the replacement instance registers it.
        shortcut.unregister()
        bothShift.stop()
        store.bothShiftAvailable = false
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    self.store.reportError("Could not reopen: \(error.localizedDescription)")
                    self.configureCaptureShortcut()
                    self.configureBothShift()
                } else { NSApp.terminate(nil) }
            }
        }
    }

    /// A shot captured just before quitting may still be saving to history.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard history.isEnabled else { return .terminateNow }
        Task { @MainActor in
            await history.settle(timeout: .seconds(3))
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        updates.installPendingUpdate()
        updates.stop()
        store.stop()
        shortcut.unregister()
        bothShift.stop()
    }

    private func configureCaptureShortcut() {
        guard !store.isRecordingShortcut else { return }
        let result = shortcut.register(shortcut: store.captureShortcut)
        store.shortcutAvailable = result.isSuccess
        if !result.isSuccess {
            store.shortcutError = result.diagnostic
            store.reportError("\(store.captureShortcutLabel) is unavailable. Choose another shortcut in settings.")
        }
    }

    private func configureBothShift() {
        if store.bothShiftEnabled && store.accessibilityGranted && !store.isRecordingShortcut {
            store.bothShiftAvailable = bothShift.start()
        } else {
            bothShift.stop()
            store.bothShiftAvailable = false
        }
    }
}
