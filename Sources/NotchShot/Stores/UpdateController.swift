// SPDX-License-Identifier: MIT
import Foundation
import Observation

/// Update policy: when to check, what to download, and when a verified update
/// may replace the running app. File and network work stays in the service.
@Observable @MainActor
final class UpdateController {
    enum Phase: Equatable {
        case unavailable(String)
        case idle
        case checking
        case upToDate
        case downloading(UpdateOffer)
        case ready(UpdateOffer)
        case installing(UpdateOffer)
        /// On disk and waiting for the next launch.
        case installed(UpdateOffer)
        case failed(String)
    }

    static let checkInterval: TimeInterval = 6 * 60 * 60
    static let retryInterval: TimeInterval = 60 * 60
    static let launchDelay: TimeInterval = 15
    static let installRetryInterval: TimeInterval = 2 * 60

    private(set) var phase: Phase
    private(set) var lastChecked: Date?
    let installation: UpdateInstallation?

    var automaticUpdates: Bool {
        didSet {
            guard oldValue != automaticUpdates else { return }
            preferences.set(automaticUpdates, forKey: "automaticUpdates")
            cancelScheduledCheck()
            cancelInstallRetry()
            if automaticUpdates {
                if started { beginCheck(userInitiated: false) }
            } else if activeCheck != nil, !activeCheckIsUserInitiated {
                // Off means no background network, including a check already under way.
                abandonCheck()
                phase = staged.map { .ready($0.offer) } ?? .idle
            }
        }
    }
    var channel: UpdateChannel {
        didSet {
            guard oldValue != channel else { return }
            preferences.set(channel.rawValue, forKey: "updateChannel")
            guard service != nil, !isInstalled else { return }
            // A check for the previous channel could stage the wrong build.
            abandonCheck()
            if let offer = staged?.offer, !channel.acceptedReleaseChannels.contains(offer.channel) { discardStaged() }
            phase = staged.map { .ready($0.offer) } ?? .idle
            if automaticUpdates && started { beginCheck(userInitiated: false) }
        }
    }

    /// Whether relaunching now would cost the user nothing (no shots, notch closed).
    @ObservationIgnored var canInstallNow: () -> Bool = { false }
    /// Opens the replaced bundle and quits this process.
    @ObservationIgnored var onRelaunch: () -> Void = {}
    @ObservationIgnored var onNotice: ((StatusNotice.Kind, String, String) -> Void)?
    /// The check in progress, if any. Tests await it.
    @ObservationIgnored private(set) var activeCheck: Task<Void, Never>?
    @ObservationIgnored private var activeCheckIsUserInitiated = false

    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let service: (any UpdateServing)?
    @ObservationIgnored private let schedule: NotchIdleTimer.Schedule
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var staged: StagedUpdate?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var cancelCheckDeadline: (() -> Void)?
    @ObservationIgnored private var cancelInstallDeadline: (() -> Void)?

    /// With no service, updates are unavailable and nothing touches the network.
    init(preferences: UserDefaults,
         installation: UpdateInstallation?,
         service: (any UpdateServing)?,
         unavailableReason: String = "Updates aren’t available for this build.",
         schedule: @escaping NotchIdleTimer.Schedule = NotchIdleTimer.scheduleTask,
         now: @escaping () -> Date = Date.init) {
        self.preferences = preferences
        self.installation = installation
        self.service = service
        self.schedule = schedule
        self.now = now
        phase = service == nil ? .unavailable(unavailableReason) : .idle
        automaticUpdates = preferences.object(forKey: "automaticUpdates") as? Bool ?? true
        channel = preferences.string(forKey: "updateChannel").flatMap(UpdateChannel.init(rawValue:))
            ?? installation?.channel ?? .stable
        lastChecked = preferences.object(forKey: "lastUpdateCheck") as? Date
    }

    static func forRunningApp(preferences: UserDefaults) -> UpdateController {
        func unavailable(_ reason: String, _ installation: UpdateInstallation? = nil) -> UpdateController {
            UpdateController(preferences: preferences, installation: installation, service: nil, unavailableReason: reason)
        }
        guard let installation = UpdateInstallation(bundle: .main) else {
            return unavailable("This build has no version number, so it can’t update itself.")
        }
        guard installation.channel != nil else {
            return unavailable("Local builds don’t update themselves. Install a release from GitHub to receive updates.", installation)
        }
        if let blocker = installation.installBlocker { return unavailable(blocker, installation) }
        do {
            let service = UpdateService(
                installation: installation,
                transport: URLSessionUpdateTransport(userAgent: "NotchShot/\(installation.version) (\(installation.build))"),
                verifier: try CodeSignatureVerifier.forRunningApp())
            return UpdateController(preferences: preferences, installation: installation, service: service)
        } catch {
            return unavailable(error.localizedDescription, installation)
        }
    }

    var isAvailable: Bool {
        if case .unavailable = phase { return false }
        return true
    }

    var isInstalled: Bool {
        if case .installed = phase { return true }
        return false
    }

    var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    /// Checks soon after launch, then about every six hours, counting time
    /// since the last check so frequent relaunches do not add requests.
    func start() {
        guard service != nil, !started else { return }
        started = true
        guard automaticUpdates else { return }
        let elapsed = lastChecked.map { max(0, now().timeIntervalSince($0)) } ?? Self.checkInterval
        scheduleCheck(after: max(Self.launchDelay, Self.checkInterval - elapsed))
    }

    func stop() {
        started = false
        cancelScheduledCheck()
        cancelInstallRetry()
        abandonCheck()
    }

    @discardableResult
    func checkNow() -> Task<Void, Never>? {
        beginCheck(userInitiated: true)
    }

    /// Installs the verified update and relaunches into it.
    func installAndRelaunch() {
        guard let service, let update = staged, !isBusy else { return }
        cancelScheduledCheck()
        cancelInstallRetry()
        phase = .installing(update.offer)
        staged = nil
        do {
            try service.install(update)
            phase = .installed(update.offer)
            onRelaunch()
        } catch {
            service.discard(update)
            phase = .failed(error.localizedDescription)
            onNotice?(.error, "Update not installed", error.localizedDescription)
            // Installing cancelled the next check; without one, updates would stop here.
            if automaticUpdates && started { scheduleCheck(after: Self.retryInterval) }
        }
    }

    /// Swaps in a verified automatic update without relaunching. Used while
    /// quitting, and before reopening for permissions, so the next launch is new.
    func installPendingUpdate() {
        guard automaticUpdates, let service, let update = staged else { return }
        if case .installing = phase { return }
        // A newer check still in flight cannot stage anything after this.
        abandonCheck()
        staged = nil
        do {
            try service.install(update)
            phase = .installed(update.offer)
        } catch {
            service.discard(update)
        }
    }

    @discardableResult
    private func beginCheck(userInitiated: Bool) -> Task<Void, Never>? {
        guard let service else { return nil }
        if let activeCheck {
            // Asking during a background check makes it the user's check.
            if userInitiated { activeCheckIsUserInitiated = true }
            return activeCheck
        }
        // The installed bundle is already newer than this running process.
        if case .installing = phase { return nil }
        if isInstalled { return nil }
        cancelScheduledCheck()
        generation &+= 1
        let token = generation
        let channel = channel
        phase = .checking
        activeCheckIsUserInitiated = userInitiated
        let task = Task { [weak self] in
            guard let self else { return }
            await self.check(service: service, channel: channel, token: token)
        }
        activeCheck = task
        return task
    }

    private func check(service: any UpdateServing, channel: UpdateChannel, token: Int) async {
        var succeeded = false
        // Read after each await: the generation check keeps this the same check.
        var userInitiated: Bool { activeCheckIsUserInitiated }
        do {
            let offer = try await service.latestOffer(for: channel)
            guard generation == token else { return }
            lastChecked = now()
            preferences.set(lastChecked, forKey: "lastUpdateCheck")
            if let offer {
                if staged?.offer != offer {
                    phase = .downloading(offer)
                    let update = try await service.stage(offer)
                    guard generation == token else { service.discard(update); return }
                    // Only a verified replacement supersedes the update waiting to install.
                    discardStaged()
                    staged = update
                }
                phase = .ready(offer)
                if userInitiated {
                    onNotice?(.info, "Update ready", automaticUpdates
                              ? "NotchShot \(offer.label) installs when the shelf is empty, or when you quit."
                              : "NotchShot \(offer.label) is ready. Restart from Settings to install it.")
                }
            } else {
                // The staged release was withdrawn from GitHub.
                discardStaged()
                phase = .upToDate
                if userInitiated { onNotice?(.success, "Up to date", "This is the newest \(channel.name.lowercased()) build.") }
            }
            succeeded = true
        } catch {
            guard generation == token else { return }
            if error is CancellationError {
                phase = staged.map { .ready($0.offer) } ?? .idle
            } else {
                // A verified update already waiting stays installable.
                phase = staged.map { .ready($0.offer) } ?? .failed(error.localizedDescription)
                if userInitiated { onNotice?(.error, "Update check failed", error.localizedDescription) }
            }
        }
        guard generation == token else { return }
        activeCheck = nil
        if automaticUpdates && started {
            scheduleCheck(after: succeeded ? Self.checkInterval : Self.retryInterval)
            installWhenIdle()
        }
    }

    /// Automatic installs wait until nothing would be lost by relaunching.
    /// Until then, quitting installs the update instead.
    private func installWhenIdle() {
        cancelInstallRetry()
        guard automaticUpdates, started, staged != nil, !isBusy else { return }
        if canInstallNow() {
            installAndRelaunch()
        } else {
            cancelInstallDeadline = schedule(.seconds(Self.installRetryInterval)) { [weak self] in
                self?.installWhenIdle()
            }
        }
    }

    private func scheduleCheck(after seconds: TimeInterval) {
        cancelScheduledCheck()
        cancelCheckDeadline = schedule(.seconds(seconds)) { [weak self] in
            guard let self, self.started, self.automaticUpdates else { return }
            self.beginCheck(userInitiated: false)
        }
    }

    private func abandonCheck() {
        generation &+= 1
        activeCheck?.cancel()
        activeCheck = nil
    }

    private func discardStaged() {
        if let staged { service?.discard(staged) }
        staged = nil
    }

    private func cancelScheduledCheck() {
        cancelCheckDeadline?()
        cancelCheckDeadline = nil
    }

    private func cancelInstallRetry() {
        cancelInstallDeadline?()
        cancelInstallDeadline = nil
    }
}
