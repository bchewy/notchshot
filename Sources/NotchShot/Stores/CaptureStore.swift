// SPDX-License-Identifier: MIT
import AppKit
import Carbon.HIToolbox
import Observation

@Observable @MainActor
final class CaptureStore {
    var isExpanded = false {
        didSet {
            cancelCopyCollapse()
            if !isExpanded {
                isRecordingShortcut = false
                // Respect closing during capture, preview, or flight. A delayed
                // result is still saved without reopening the notch.
                suppressCaptureArrival()
            }
        }
    }
    var page: NotchPage = .shelf {
        didSet {
            cancelCopyCollapse()
            if page != .settings { isRecordingShortcut = false }
        }
    }
    var showingSettings: Bool {
        get { page == .settings }
        set {
            if newValue { suppressCaptureArrival() }
            page = newValue ? .settings : .shelf
        }
    }
    private(set) var captureShortcut: CaptureShortcut
    var shortcutError: String?
    var isRecordingShortcut = false {
        didSet {
            guard oldValue != isRecordingShortcut else { return }
            cancelCopyCollapse()
            if isRecordingShortcut { assistedPaste.cancel(); shortcutError = nil }
            onShortcutRecordingChanged?(isRecordingShortcut)
        }
    }
    var isCapturing = false {
        didSet { cancelCopyCollapse() }
    }
    var isImporting = false {
        didSet { cancelCopyCollapse() }
    }
    var isDropTargeted = false {
        didSet { cancelCopyCollapse() }
    }
    var pendingCapture: CaptureResult? {
        didSet {
            cancelCopyCollapse()
            if oldValue?.id != pendingCapture?.id { cancelLanding() }
        }
    }
    var isLandingCapture = false {
        didSet { cancelCopyCollapse() }
    }
    var autoCollectCaptures = true
    var bothShiftEnabled: Bool {
        didSet {
            preferences.set(bothShiftEnabled, forKey: "bothShiftEnabled")
            onShortcutSettingsChanged?()
        }
    }
    var captureSoundEnabled: Bool {
        didSet { preferences.set(captureSoundEnabled, forKey: "captureSoundEnabled") }
    }
    var copySoundEnabled: Bool {
        didSet { preferences.set(copySoundEnabled, forKey: "copySoundEnabled") }
    }
    var collapseAfterCopy: Bool {
        didSet {
            preferences.set(collapseAfterCopy, forKey: "collapseAfterCopy")
            if !collapseAfterCopy { cancelCopyCollapse() }
        }
    }
    var autoCollapseEnabled: Bool {
        didSet {
            preferences.set(autoCollapseEnabled, forKey: "autoCollapseEnabled")
            refreshAutoCollapse(restart: true)
        }
    }
    private var idleDelaySeconds: Double
    var autoCollapseDelay: Double {
        get { idleDelaySeconds }
        set {
            idleDelaySeconds = Self.validAutoCollapseDelay(newValue)
            preferences.set(idleDelaySeconds, forKey: "autoCollapseDelay")
            refreshAutoCollapse(restart: true)
        }
    }
    var autoCopyCapture: Bool {
        didSet { preferences.set(autoCopyCapture, forKey: "autoCopyCapture") }
    }
    var pasteImageThenText: Bool {
        didSet {
            preferences.set(pasteImageThenText, forKey: "pasteImageThenText")
            if !pasteImageThenText { assistedPaste.cancel() }
        }
    }
    var openShelfAfterCapture: Bool {
        didSet { preferences.set(openShelfAfterCapture, forKey: "openShelfAfterCapture") }
    }
    private var soundVolume: Double
    var captureSoundVolume: Double {
        get { soundVolume }
        set {
            soundVolume = Self.validSoundVolume(newValue)
            preferences.set(soundVolume, forKey: "captureSoundVolume")
            captureSound.setVolume(Float(soundVolume))
            copySound.setVolume(Float(soundVolume))
        }
    }
    var captureShutterSound: CaptureShutterSound {
        didSet {
            preferences.set(captureShutterSound.rawValue, forKey: "captureShutterSound")
            captureSound.select(captureShutterSound)
        }
    }
    var captures: [CaptureResult] = [] {
        didSet {
            shelfSelection.reconcile(orderedIDs: captures.map(\.id))
            rebuildSelectedBatch()
            cancelCopyCollapse()
        }
    }
    private var shelfSelection = ShelfSelection()
    var isSelectingShots: Bool { shelfSelection.isActive }
    var selectedShotIDs: Set<UUID> { shelfSelection.ids }
    var selectedShotCount: Int { shelfSelection.ids.count }
    var selectedShelfCaptures: [CaptureResult] { captures.filter { shelfSelection.ids.contains($0.id) } }
    private(set) var selectedBatch: CaptureBatch?
    private(set) var isPreparingBatch = false {
        didSet { cancelCopyCollapse() }
    }
    var batchContextStyle: BatchContextStyle {
        didSet {
            preferences.set(batchContextStyle.rawValue, forKey: "batchContextStyle")
            rebuildSelectedBatch()
            cancelCopyCollapse()
        }
    }
    var selectedID: UUID? {
        didSet { if oldValue != selectedID { cancelCopyCollapse() } }
    }
    var activeAppName = "your active app"
    private(set) var statusNotice: StatusNotice?
    var accessibilityGranted = false
    var screenRecordingGranted = false
    var shortcutAvailable = true
    var bothShiftAvailable = false
    var notchHeight: CGFloat = 32
    var notchWidth: CGFloat = 190
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let captureSound: any CaptureSoundPlaying
    @ObservationIgnored private let copySound: any CopySoundPlaying
    @ObservationIgnored private let clipboard: NSPasteboard
    @ObservationIgnored private let assistedPaste: any AssistedPasteServing
    @ObservationIgnored private var lastAutoCopiedID: UUID?
    @ObservationIgnored var onRegisterShortcut: ((CaptureShortcut) -> GlobalShortcutService.RegistrationResult)?
    @ObservationIgnored var onShortcutRecordingChanged: ((Bool) -> Void)?
    @ObservationIgnored var onReopen: (() -> Void)?
    @ObservationIgnored var onPresentCard: ((CaptureResult) -> Void)?
    @ObservationIgnored var onDismissCard: (() -> Void)?
    @ObservationIgnored var onLandCard: ((@escaping () -> Void) -> Void)?
    @ObservationIgnored var onShortcutSettingsChanged: (() -> Void)?
    @ObservationIgnored var onRefreshNotchAttention: (() -> Void)?
    @ObservationIgnored var onExportPresentationChange: ((Bool) -> Void)?
    /// The incoming thumbnail's actual AppKit screen-space bounds.
    @ObservationIgnored private(set) var shelfLandingFrame: CGRect?
    @ObservationIgnored private var shelfLandingFrameOwner: UUID?

    @ObservationIgnored private var lastExternalTarget: CaptureTarget?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var permissionTimer: Timer?
    @ObservationIgnored private let captureService: any CaptureServing
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var historyRevision = 0
    @ObservationIgnored private var landingTask: Task<Void, Never>?
    @ObservationIgnored private var landingRevision = 0
    @ObservationIgnored private let landingPreviewDelay: Duration
    @ObservationIgnored private let shelfPreparationDelay: Duration
    @ObservationIgnored private let copyCollapseDelay: Duration
    @ObservationIgnored private let copyCollapseSchedule: NotchIdleTimer.Schedule
    @ObservationIgnored private var cancelCopyCollapseDeadline: (() -> Void)?
    @ObservationIgnored private var copyCollapseGeneration = 0
    private var isDraggingCard = false {
        didSet { cancelCopyCollapse() }
    }
    @ObservationIgnored private var dismissedCaptureRevision: Int?
    @ObservationIgnored private var captureRevision = 0
    @ObservationIgnored private var arrivalSuppressedRevision: Int?
    private var isPresentingExport = false {
        didSet { cancelCopyCollapse() }
    }
    @ObservationIgnored private var idleTimer: NotchIdleTimer?
    @ObservationIgnored private var idleTimerStopped = false
    @ObservationIgnored private var pointerInsideNotch = false
    @ObservationIgnored private var notchKeyboardFocused = false
    @ObservationIgnored private var notchMenuTracking = false
    @ObservationIgnored private var notchMouseButtonDown = false
    @ObservationIgnored private var notchSurfaceVisible = false
    @ObservationIgnored private var autoCollapseProtections: Set<UUID> = []
    @ObservationIgnored private let batchPreparer = CaptureBatchPreparer()
    @ObservationIgnored private var batchPreparationTask: Task<Void, Never>?
    @ObservationIgnored private var batchPreparationRevision = 0

    /// Preferences and the pasteboard have no defaults so a test cannot reach
    /// the real ones without saying so.
    init(preferences: UserDefaults,
         landingPreviewDelay: Duration = .milliseconds(550),
         shelfPreparationDelay: Duration = .milliseconds(280),
         captureSound: (any CaptureSoundPlaying)? = nil,
         clipboard: NSPasteboard,
         copySound: (any CopySoundPlaying)? = nil,
         copyCollapseDelay: Duration = .milliseconds(180),
         copyCollapseSchedule: @escaping NotchIdleTimer.Schedule = NotchIdleTimer.scheduleTask,
         assistedPaste: (any AssistedPasteServing)? = nil,
         idleSchedule: @escaping NotchIdleTimer.Schedule = NotchIdleTimer.scheduleTask,
         captureService: (any CaptureServing)? = nil) {
        self.preferences = preferences
        self.captureService = captureService ?? CaptureService()
        self.captureSound = captureSound ?? CaptureSoundService()
        self.clipboard = clipboard
        self.copySound = copySound ?? CopySoundService()
        self.assistedPaste = assistedPaste ?? AssistedPasteService()
        self.landingPreviewDelay = landingPreviewDelay
        self.shelfPreparationDelay = shelfPreparationDelay
        self.copyCollapseDelay = copyCollapseDelay
        self.copyCollapseSchedule = copyCollapseSchedule
        batchContextStyle = preferences.string(forKey: "batchContextStyle")
            .flatMap(BatchContextStyle.init(rawValue:)) ?? .compact
        captureShortcut = CaptureShortcut.load(from: preferences)
        // Preserve whether the optional gesture was enabled during upgrades,
        // then use its own key so an old preference cannot override new choices.
        bothShiftEnabled = preferences.object(forKey: "bothShiftEnabled") as? Bool
            ?? preferences.object(forKey: "doubleShiftEnabled") as? Bool
            ?? preferences.object(forKey: "doubleCommandEnabled") as? Bool ?? true
        captureSoundEnabled = preferences.object(forKey: "captureSoundEnabled") as? Bool ?? true
        copySoundEnabled = preferences.object(forKey: "copySoundEnabled") as? Bool ?? true
        collapseAfterCopy = preferences.object(forKey: "collapseAfterCopy") as? Bool ?? true
        autoCollapseEnabled = preferences.object(forKey: "autoCollapseEnabled") as? Bool ?? true
        idleDelaySeconds = Self.validAutoCollapseDelay(preferences.object(forKey: "autoCollapseDelay") as? Double ?? 3)
        autoCopyCapture = preferences.object(forKey: "autoCopyCapture") as? Bool ?? false
        pasteImageThenText = preferences.object(forKey: "pasteImageThenText") as? Bool ?? false
        openShelfAfterCapture = preferences.object(forKey: "openShelfAfterCapture") as? Bool ?? true
        soundVolume = Self.validSoundVolume(preferences.object(forKey: "captureSoundVolume") as? Double ?? 0.65)
        captureShutterSound = preferences.string(forKey: "captureShutterSound")
            .flatMap(CaptureShutterSound.init(rawValue:)) ?? .defaultSound
        preferences.set(bothShiftEnabled, forKey: "bothShiftEnabled")
        self.captureSound.select(captureShutterSound)
        self.captureSound.setVolume(Float(soundVolume))
        self.copySound.setVolume(Float(soundVolume))
        idleTimer = NotchIdleTimer(schedule: idleSchedule,
                                   refreshAttention: { [weak self] in self?.onRefreshNotchAttention?() },
                                   collapse: { [weak self] in self?.collapse() })
        self.assistedPaste.onResult = { [weak self] result in
            switch result {
            case .eventsSent: break
            case .cancelled(let reason): self?.report(.info, "Paste assistance", message: reason)
            case .unavailable(let reason): self?.report(.info, "Paste assistance", message: reason)
            case .failed(let reason): self?.reportError(reason)
            }
        }
    }

    private static func validAutoCollapseDelay(_ value: Double) -> Double {
        [2.0, 3.0, 5.0, 10.0].contains(value) ? value : 3
    }

    /// The AppKit bridge reports presence; all dismissal policy stays here.
    func updateNotchAttention(pointerInside: Bool, keyboardFocused: Bool,
                              menuTracking: Bool, mouseButtonDown: Bool, surfaceVisible: Bool) {
        pointerInsideNotch = pointerInside
        notchKeyboardFocused = keyboardFocused
        notchMenuTracking = menuTracking
        notchMouseButtonDown = mouseButtonDown
        notchSurfaceVisible = surfaceVisible
        refreshAutoCollapse()
    }

    // Native key/mouse releases are still part of the same copy gesture. They
    // reset idle time without cancelling the separate copied-feedback close.
    func noteNotchActivity() { refreshAutoCollapse(restart: true) }

    /// Popovers can extend outside the panel. Each owns its own protection so
    /// dismissing one cannot accidentally remove another's protection.
    func setAutoCollapseProtection(owner: UUID, active: Bool) {
        if active {
            autoCollapseProtections.insert(owner)
            cancelCopyCollapse()
        } else {
            autoCollapseProtections.remove(owner)
            // Closing the review after Copy is part of that same action. Keep
            // its confirmation-close alive while restarting the idle timer.
            refreshAutoCollapse(restart: true)
        }
    }

    /// Work the notch must not close under. Both collapse policies derive from
    /// this one list, so a new busy state is added here and nowhere else.
    private var isInteractionInProgress: Bool {
        isCapturing || isImporting || isDropTargeted || isDraggingCard || isLandingCapture
            || isRecordingShortcut || isPresentingExport || pendingCapture != nil || isPreparingBatch
    }

    private func refreshAutoCollapse(restart: Bool = false) {
        let eligible = !idleTimerStopped && autoCollapseEnabled && isExpanded && notchSurfaceVisible
            && !pointerInsideNotch && !notchKeyboardFocused && !notchMenuTracking
            && !notchMouseButtonDown && autoCollapseProtections.isEmpty && !isInteractionInProgress
        idleTimer?.update(eligible: eligible, delay: .seconds(autoCollapseDelay), restart: restart)
    }

    private static func validSoundVolume(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0.65
    }

    var captureShortcutLabel: String { captureShortcut.displayString }
    var usesBothShiftForCaptureHint: Bool { bothShiftEnabled && accessibilityGranted && bothShiftAvailable }
    var captureHintLabel: String { usesBothShiftForCaptureHint ? "⇧ + ⇧" : captureShortcutLabel }
    var captureHintHelp: String {
        usesBothShiftForCaptureHint
            ? "Press left Shift + right Shift together to capture the frontmost app."
            : "Press \(captureShortcutLabel) to capture the frontmost app."
    }
    var hasAvailableCaptureShortcut: Bool { usesBothShiftForCaptureHint || shortcutAvailable }

    /// Feedback shown in the notch. The producer names the kind and title, so
    /// rewording a message can never change how long it stays or how it looks.
    func report(_ kind: StatusNotice.Kind, _ title: String, message: String, revealURL: URL? = nil) {
        statusNotice = StatusNotice(kind: kind, title: title, message: message, revealURL: revealURL)
    }

    func reportError(_ message: String) {
        report(.error, "Needs attention", message: message)
    }

    func clearStatus() {
        statusNotice = nil
    }

    func beginShelfSelection() {
        shelfSelection.begin()
        cancelCopyCollapse()
    }

    func endShelfSelection() {
        shelfSelection.end()
        rebuildSelectedBatch()
        cancelCopyCollapse()
    }

    func selectAllShelfShots() {
        shelfSelection.selectAll(orderedIDs: captures.map(\.id))
        rebuildSelectedBatch()
        cancelCopyCollapse()
    }

    func handleShelfClick(_ id: UUID, commandPressed: Bool = false, shiftPressed: Bool = false) {
        guard captures.contains(where: { $0.id == id }) else { return }
        if shiftPressed {
            shelfSelection.extend(to: id, orderedIDs: captures.map(\.id))
        } else if commandPressed || isSelectingShots {
            shelfSelection.toggle(id, orderedIDs: captures.map(\.id))
        } else {
            showCaptureDetail(id)
            return
        }
        rebuildSelectedBatch()
        cancelCopyCollapse()
    }

    private func rebuildSelectedBatch() {
        batchPreparationTask?.cancel()
        batchPreparationTask = nil
        batchPreparationRevision &+= 1
        let selected = selectedShelfCaptures
        selectedBatch = nil
        guard !selected.isEmpty else { isPreparingBatch = false; return }
        let needsBackgroundWork = selected.contains {
            $0.pngData != nil || !$0.axTree.isEmpty ||
                $0.accessibilityText.utf8.count + $0.ocrText.utf8.count + $0.importedText.utf8.count > 128_000
        }
        guard needsBackgroundWork else {
            selectedBatch = CaptureBatch(captures: selected, contextStyle: batchContextStyle)
            isPreparingBatch = false
            return
        }
        isPreparingBatch = true
        let revision = batchPreparationRevision
        let style = batchContextStyle
        let preparer = batchPreparer
        batchPreparationTask = Task { [weak self] in
            let batch = await preparer.prepare(captures: selected, style: style)
            guard !Task.isCancelled, let self, self.batchPreparationRevision == revision else { return }
            self.selectedBatch = batch
            self.isPreparingBatch = false
            self.batchPreparationTask = nil
        }
    }

    /// During explicit batch selection every hovered thumbnail copies that batch;
    /// entering an unselected thumbnail must never silently replace the selection.
    @discardableResult
    func copyShelfShot(_ id: UUID) -> Bool {
        guard captures.contains(where: { $0.id == id }) else { return false }
        if isSelectingShots { return copyShelfSelection() }
        return copyCapture(id)
    }

    @discardableResult
    func copyShelfSelection() -> Bool {
        guard isSelectingShots, !isPreparingBatch, let batch = selectedBatch, !batch.captures.isEmpty else { return false }
        assistedPaste.cancel()
        // Finish all representation building before replacing the clipboard.
        let item = CaptureClipboardService.makeItem(for: batch)
        clipboard.clearContents()
        guard clipboard.writeObjects([item]) else {
            reportError("Could not copy the selected shots.")
            return false
        }
        let count = batch.captures.count
        let label = count == 1 ? "1 shot" : "\(count) shots"
        let compact = batch.isShortened ? " Compact context; full text remains in your shots." : ""
        let unavailable = batch.omittedScreenshotNumbers.isEmpty ? "" :
            " Screenshots unavailable for shots \(batch.omittedScreenshotNumbers.map(String.init).joined(separator: ", ")); their text is included."
        report(.success, "Copied", message: "\(label) copied.\(compact)\(unavailable)")
        if pasteImageThenText && !batch.imagePNGs.isEmpty {
            if captureShortcut == CaptureShortcut(keyCode: UInt16(kVK_ANSI_V), modifierFlags: .command) {
                report(.info, "Paste assistance", message: "\(label) copied. Choose a capture shortcut other than ⌘V to use paste assistance.")
            } else if assistedPaste.arm(batch: batch, clipboard: clipboard) {
                report(.info, "Paste assistance", message: "\(label) copied. Your next ⌘V pastes the screenshots in order, then their context. Wait for pasting to finish.\(compact)\(unavailable)")
            }
        }
        confirmManualCopy()
        return true
    }

    func showShelf() {
        page = .shelf
        isExpanded = true
        refreshPermissions()
    }

    func showCaptureSettings() {
        // A user choosing another page owns navigation from this point. Finish
        // any completed arrival so its delayed completion cannot switch back.
        suppressCaptureArrival()
        page = .settings
        isExpanded = true
        refreshPermissions()
    }

    func showCaptureDetail(_ id: UUID) {
        guard captures.contains(where: { $0.id == id }) else { return }
        suppressCaptureArrival()
        // Collecting the incoming capture can evict the oldest shelf item.
        guard captures.contains(where: { $0.id == id }) else { return }
        selectedID = id
        page = .detail
        isExpanded = true
    }

    func setCaptureShortcut(_ candidate: CaptureShortcut) {
        guard let register = onRegisterShortcut else {
            shortcutError = "Shortcut setup is not ready. Reopen NotchShot and try again."
            return
        }
        let result = register(candidate)
        guard result.isSuccess else {
            shortcutError = result.diagnostic ?? "That shortcut is unavailable. Try another combination."
            return
        }
        captureShortcut = candidate
        candidate.save(to: preferences)
        shortcutAvailable = true
        shortcutError = nil
        report(.success, "Shortcut saved", message: "Capture shortcut set to \(candidate.displayString).")
    }

    func resetCaptureShortcut() {
        isRecordingShortcut = false
        setCaptureShortcut(.defaultShortcut)
    }

    var selectedCapture: CaptureResult? {
        captures.first { $0.id == selectedID } ?? captures.first
    }

    func start() {
        idleTimerStopped = false
        refreshAutoCollapse()
        updateTarget(captureService.frontmostTarget())
        refreshPermissions()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // The app in front now, not the one the notification named. They
                // agree in practice, and this keeps the store on the capture seam.
                self.updateTarget(self.captureService.frontmostTarget())
                self.refreshPermissions()
            }
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isExpanded else { return }
                self.refreshPermissions()
            }
        }
    }

    func stop() {
        idleTimerStopped = true
        idleTimer?.stop()
        batchPreparationRevision &+= 1
        batchPreparationTask?.cancel()
        batchPreparationTask = nil
        isPreparingBatch = false
        assistedPaste.stop()
        cancelCopyCollapse()
        isRecordingShortcut = false
        cancelLanding()
        cancelCapture()
        permissionTimer?.invalidate()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }

    private func updateTarget(_ target: CaptureTarget?) {
        guard let target else { return }
        lastExternalTarget = target
        activeAppName = target.appName
    }

    func captureFrontmost() {
        guard !isCapturing, !isPresentingExport, !isImporting, !isDraggingCard, !isRecordingShortcut else { return }
        assistedPaste.cancel()
        updateTarget(captureService.frontmostTarget())
        guard let target = lastExternalTarget else {
            report(.info, "Open an app", message: "Open an app window, then press \(captureHintLabel) to capture it.")
            showShelf()
            return
        }
        refreshPermissions()
        guard accessibilityGranted || screenRecordingGranted else {
            report(.info, "Set up capture", message: "Enable the permissions below, then capture your app.")
            showCaptureSettings()
            return
        }
        // Finish collecting the previous card before starting another capture.
        if pendingCapture != nil {
            acceptPendingCapture(expandShelf: isExpanded && openShelfAfterCapture,
                                 preserveNavigation: !openShelfAfterCapture)
        }
        arrivalSuppressedRevision = nil
        isCapturing = true
        // A window capture excludes our overlay. Keep the notch where the user
        // left it rather than closing and reopening it around every capture.
        if isExpanded && openShelfAfterCapture { page = .shelf }
        clearStatus()
        captureRevision += 1
        let request = captureRevision
        var sounded = false
        captureTask = Task {
            let outcome: Result<CaptureResult, Error>
            do {
                outcome = .success(try await captureService.capture(target: target) { [weak self] partial in
                    guard let self, request == self.captureRevision,
                          self.dismissedCaptureRevision != request else { return }
                    self.pendingCapture = partial
                    if self.arrivalSuppressedRevision != request { self.onPresentCard?(partial) }
                    if !sounded { self.playCaptureSound(); sounded = true }
                })
            } catch { outcome = .failure(error) }
            // A cancelled request has already released the busy flag, and a
            // newer request may own it now.
            guard request == captureRevision else { return }
            isCapturing = false
            captureTask = nil
            switch outcome {
            case .success(let result):
                guard dismissedCaptureRevision != request else { return }
                pendingCapture = result
                autoCopyCompletedCapture(result)
                if arrivalSuppressedRevision != request { onPresentCard?(result) }
                if !sounded { playCaptureSound() }
                scheduleLanding()
            case .failure(let error):
                dismissPendingCapture()
                reportError(error.localizedDescription)
                if arrivalSuppressedRevision != request {
                    if accessibilityGranted || screenRecordingGranted { showShelf() }
                    else { showCaptureSettings() }
                }
            }
            refreshPermissions()
        }
    }

    /// Clearing the shelf or stopping the store abandons a capture in flight
    /// instead of letting it finish, hold its PNG, and block the next capture.
    /// Bumping the revision makes the abandoned task's callbacks stale, which
    /// is also why the capture path needs no history check of its own.
    private func cancelCapture() {
        captureTask?.cancel()
        captureTask = nil
        captureRevision += 1
        isCapturing = false
    }

    func toggleExpanded() {
        if isExpanded { collapse() } else { showShelf() }
    }
    func collapse() { isExpanded = false }
    func removeCapture(_ id: UUID) {
        guard let index = captures.firstIndex(where: { $0.id == id }) else { return }
        let removed = captures[index]
        let wasSelected = selectedCapture?.id == id
        captures.remove(at: index)
        if wasSelected {
            selectedID = captures.isEmpty ? nil : captures[min(index, captures.count - 1)].id
        }
        if captures.isEmpty && page == .detail { page = .shelf }
        // Removing one saved shot must not invalidate another capture/import
        // in flight, move away from surviving shots, or clear the rest of the session.
        report(.success, "Removed", message: "Removed \(removed.appName) shot.")
    }

    func clearHistory() {
        historyRevision += 1
        cancelCapture()
        dismissPendingCapture()
        captures.removeAll()
        selectedID = nil
        page = .shelf
        report(.success, "Cleared", message: "Session captures cleared.")
    }

    func refreshPermissions() {
        let permissions = captureService.permissionStatus()
        accessibilityGranted = permissions.accessibility
        screenRecordingGranted = permissions.screenRecording
        onShortcutSettingsChanged?()
    }
    func requestAccessibility() {
        collapse()
        PermissionService.requestAccessibility()
        refreshPermissions()
    }
    func requestScreenRecording() {
        collapse()
        PermissionService.requestScreenRecording()
        refreshPermissions()
    }

    func reopenForPermissions() {
        onReopen?()
    }

    func acceptPendingCapture() {
        acceptPendingCapture(expandShelf: true)
    }

    private func acceptPendingCapture(expandShelf: Bool, preserveNavigation: Bool = false) {
        guard !isCapturing, let capture = pendingCapture else { return }
        autoCopyCompletedCapture(capture)
        cancelLanding()
        pendingCapture = nil
        onDismissCard?()
        collect(capture, expandShelf: expandShelf, preserveNavigation: preserveNavigation)
    }

    private func suppressCaptureArrival() {
        if isCapturing {
            arrivalSuppressedRevision = captureRevision
            cancelLanding()
            onDismissCard?()
        } else if pendingCapture != nil {
            acceptPendingCapture(expandShelf: false, preserveNavigation: true)
        }
    }

    func dismissPendingCapture() {
        cancelLanding()
        dismissedCaptureRevision = captureRevision
        pendingCapture = nil
        onDismissCard?()
    }

    private func collect(_ capture: CaptureResult, expandShelf: Bool = true, preserveNavigation: Bool = false) {
        let previousSelection = selectedID
        captures.removeAll { $0.id == capture.id }
        captures.insert(capture, at: 0)
        while captures.count > 8 || (captures.count > 1 && captures.reduce(0, { $0 + ($1.pngData?.count ?? 0) }) > 64 * 1024 * 1024) {
            // A quiet arrival must not replace the detail the user just chose.
            // Retain it alongside the incoming shot until the user leaves it.
            let protectedID = preserveNavigation && page == .detail ? previousSelection : nil
            guard let removable = captures.indices.reversed().first(where: { $0 > 0 && captures[$0].id != protectedID }) else { break }
            captures.remove(at: removable)
        }
        selectedID = preserveNavigation && captures.contains(where: { $0.id == previousSelection })
            ? previousSelection : capture.id
        if !preserveNavigation { page = .shelf }
        if expandShelf { isExpanded = true }
        isDropTargeted = false
        let imported = capture.bundleIdentifier.isEmpty
        let copied = lastAutoCopiedID == capture.id
        let summary = imported
            ? "Added \(capture.windowTitle) to your shelf."
            : "Captured \(capture.appName) · \(capture.elementCount) accessibility elements"
        report(.success, copied ? "Copied" : (imported ? "Added" : "Captured"),
               message: copied ? summary + " · copied" : summary)
    }

    private func scheduleLanding() {
        cancelLanding()
        if arrivalSuppressedRevision == captureRevision {
            acceptPendingCapture(expandShelf: false, preserveNavigation: true)
            return
        }
        guard autoCollectCaptures, !isCapturing, !isDraggingCard, let id = pendingCapture?.id else { return }
        let revision = landingRevision
        let previewDelay = landingPreviewDelay
        let preparationDelay = shelfPreparationDelay
        landingTask = Task { [weak self] in
            do { try await Task.sleep(for: previewDelay) } catch { return }
            guard let self, self.landingRevision == revision,
                  self.pendingCapture?.id == id, !self.isDraggingCard else { return }
            // Reserve a slot if visible, or fly into the collapsed notch when
            // the user has disabled automatic opening.
            let shouldOpen = self.openShelfAfterCapture
            self.isLandingCapture = true
            if shouldOpen || (self.isExpanded && self.page == .shelf) {
                self.showShelf()
                do { try await Task.sleep(for: preparationDelay) } catch { return }
            }
            guard self.landingRevision == revision, self.pendingCapture?.id == id,
                  !self.isDraggingCard else { return }
            let finish: () -> Void = { [weak self] in
                guard let self, self.landingRevision == revision,
                      self.pendingCapture?.id == id, !self.isDraggingCard else { return }
                self.acceptPendingCapture(expandShelf: shouldOpen, preserveNavigation: !shouldOpen)
            }
            if let land = self.onLandCard { land(finish) } else { finish() }
        }
    }

    func beginCardDrag() {
        cancelLanding()
        isDraggingCard = true
        showShelf()
    }

    private func cancelLanding() {
        landingRevision += 1
        landingTask?.cancel()
        landingTask = nil
        isLandingCapture = false
        shelfLandingFrame = nil
        shelfLandingFrameOwner = nil
    }

    func reportShelfLandingFrame(_ frame: CGRect, captureID: UUID, owner: UUID) {
        guard isLandingCapture, pendingCapture?.id == captureID,
              !frame.isEmpty, !frame.isInfinite, !frame.isNull else { return }
        shelfLandingFrameOwner = owner
        shelfLandingFrame = frame
    }

    func clearShelfLandingFrame(owner: UUID) {
        guard shelfLandingFrameOwner == owner else { return }
        shelfLandingFrame = nil
        shelfLandingFrameOwner = nil
    }

    func endCardDrag(accepted: Bool) {
        isDraggingCard = false
        isDropTargeted = false
        // Also retain a shot dragged to another app in our local shelf.
        if accepted { acceptPendingCapture() } else { scheduleLanding() }
    }

    func canReceiveDrop(_ pasteboard: NSPasteboard) -> Bool {
        guard !isImporting, !isCapturing, !isPresentingExport else { return false }
        if let raw = pasteboard.string(forType: CaptureCardPasteboard.captureID), let id = UUID(uuidString: raw) {
            return pendingCapture?.id == id || captures.contains { $0.id == id }
        }
        return CaptureImportService.canImport(pasteboard)
    }

    @discardableResult
    func receiveDrop(_ pasteboard: NSPasteboard) -> Bool {
        guard canReceiveDrop(pasteboard) else { return false }
        isDropTargeted = false
        if let raw = pasteboard.string(forType: CaptureCardPasteboard.captureID), let id = UUID(uuidString: raw) {
            if pendingCapture?.id == id { acceptPendingCapture() }
            else { selectedID = id; showShelf() }
            return true
        }
        do {
            // Materialize the drag's contents before AppKit ends its session.
            let payload = try CaptureImportService.snapshot(from: pasteboard)
            let revision = historyRevision
            isImporting = true
            showShelf()
            report(.info, "Adding…", message: "Adding dropped Appshot…")
            Task {
                defer { isImporting = false }
                do {
                    let imported = try await CaptureImportService.importCapture(payload: payload)
                    guard revision == historyRevision else { return }
                    collect(imported)
                    playCaptureSound()
                } catch {
                    if revision == historyRevision { reportError(error.localizedDescription) }
                }
            }
            return true
        } catch {
            reportError(error.localizedDescription)
            showShelf()
            return false
        }
    }

    private func playCaptureSound() {
        guard captureSoundEnabled else { return }
        captureSound.play()
    }

    /// Explicit settings auditions are independent of automatic capture audio.
    func previewCaptureSound() {
        captureSound.play()
    }

    func copyImage() {
        guard let png = selectedCapture?.pngData else { return }
        assistedPaste.cancel()
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        clipboard.clearContents()
        let success = clipboard.writeObjects([item])
        if success { report(.success, "Copied", message: "Screenshot copied.") } else { reportError("Could not copy the screenshot.") }
        if success { confirmManualCopy() }
    }
    func copyText() {
        guard let capture = selectedCapture else { return }
        var sections: [String] = []
        if !capture.accessibilityText.isEmpty { sections.append("Accessibility text\n\(capture.accessibilityText)") }
        if !capture.ocrText.isEmpty { sections.append("Text recognized from screenshot (OCR)\n\(capture.ocrText)") }
        if !capture.importedText.isEmpty { sections.append("Imported text\n\(capture.importedText)") }
        copy(sections.joined(separator: "\n\n"), message: "Text copied with its source labels.")
    }
    func copyTree() {
        guard let capture = selectedCapture, !capture.axTree.isEmpty else { return }
        copy(capture.treeText, message: "Accessibility tree copied.")
    }
    func copyContext() {
        guard let capture = selectedCapture else { return }
        _ = copyCapture(capture.id)
    }

    /// Hover copy preserves selection; successful manual copies may close the
    /// panel after confirmation. Deleted/stale IDs never touch the clipboard.
    @discardableResult
    func copyCapture(_ id: UUID) -> Bool {
        guard let capture = captures.first(where: { $0.id == id }) else { return false }
        let success = writeCaptureToClipboard(capture)
        if success { report(.success, "Copied", message: "\(capture.appName) shot copied.") } else { reportError("Could not copy the capture.") }
        if success { armAssistedPaste(for: capture); confirmManualCopy() }
        return success
    }

    /// Called only after the complete capture is ready, never from its partial
    /// screenshot callback. Repeated completion/collection cannot recopy it.
    func autoCopyCompletedCapture(_ capture: CaptureResult) {
        guard autoCopyCapture, !isCapturing, lastAutoCopiedID != capture.id else { return }
        if writeCaptureToClipboard(capture) {
            lastAutoCopiedID = capture.id
            report(.success, "Copied", message: "\(capture.appName) shot copied.")
            armAssistedPaste(for: capture)
            playCopySound()
        } else { reportError("Could not copy the capture.") }
    }

    private func writeCaptureToClipboard(_ capture: CaptureResult) -> Bool {
        assistedPaste.cancel()
        let item = CaptureClipboardService.makeItem(for: capture)
        clipboard.clearContents()
        return clipboard.writeObjects([item])
    }

    private func armAssistedPaste(for capture: CaptureResult) {
        guard pasteImageThenText, capture.pngData != nil else { return }
        guard captureShortcut != CaptureShortcut(keyCode: UInt16(kVK_ANSI_V), modifierFlags: .command) else {
            report(.info, "Paste assistance", message: "Shot copied. Choose a capture shortcut other than ⌘V to use Paste image, then text.")
            return
        }
        if assistedPaste.arm(capture: capture, clipboard: clipboard) {
            report(.info, "Paste assistance", message: "Shot copied. Your next ⌘V pastes the image, then its text.")
        }
    }
    private func copy(_ text: String, message: String) {
        guard !text.isEmpty else { return }
        assistedPaste.cancel()
        clipboard.clearContents()
        let success = clipboard.setString(text, forType: .string)
        if success { report(.success, "Copied", message: message) } else { reportError("Could not copy text.") }
        if success { confirmManualCopy() }
    }

    private var canCollapseAfterCopy: Bool {
        collapseAfterCopy && isExpanded && page != .settings && !isInteractionInProgress
    }

    private func confirmManualCopy() {
        playCopySound()
        cancelCopyCollapse()
        guard canCollapseAfterCopy else { return }
        let generation = copyCollapseGeneration
        cancelCopyCollapseDeadline = copyCollapseSchedule(copyCollapseDelay) { [weak self] in
            // Cancellation may race with a callback that is already queued.
            guard let self, self.copyCollapseGeneration == generation, self.canCollapseAfterCopy else { return }
            self.cancelCopyCollapseDeadline = nil
            // Reuse the interruptible native spring and Reduce Motion handling.
            self.collapse()
        }
    }

    /// Explicit navigation inside a detail page also owns the next interaction.
    func cancelCopyCollapse() {
        copyCollapseGeneration &+= 1
        cancelCopyCollapseDeadline?()
        cancelCopyCollapseDeadline = nil
        refreshAutoCollapse(restart: true)
    }

    private func playCopySound() {
        guard copySoundEnabled else { return }
        copySound.play()
    }

    func exportSelected() {
        guard !isPresentingExport, let capture = selectedCapture else { return }
        let panel = NSOpenPanel()
        panel.title = "Export NotchShot"
        panel.message = "Choose a folder for the screenshot, text, and accessibility tree."
        panel.prompt = "Export here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        // Release the nonactivating notch's key focus before opening the chooser.
        isPresentingExport = true
        isExpanded = false
        onExportPresentationChange?(true)
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            Task { @MainActor in
                guard let self else { return }
                self.isPresentingExport = false
                self.isExpanded = true
                self.onExportPresentationChange?(false)
                guard response == .OK, let directory = panel.url else { return }
                do {
                    let folder = try ExportService.export(capture, to: directory)
                    self.report(.success, "Exported", message: "Exported to \(folder.lastPathComponent).", revealURL: folder)
                    NSWorkspace.shared.activateFileViewerSelecting([folder])
                } catch { self.reportError("Export failed: \(error.localizedDescription)") }
            }
        }
    }
}
