// SPDX-License-Identifier: MIT
import AppKit
import Observation

/// Opt-in history of shots, saved on this Mac. The shelf stays the working
/// set; history keeps every shot until its retention ends, unless pinned.
@Observable @MainActor
final class ShotHistory {
    enum Retention: String, CaseIterable, Identifiable {
        case week, month, quarter, forever

        var id: String { rawValue }
        var label: String {
            switch self {
            case .week: "1 week"
            case .month: "1 month"
            case .quarter: "3 months"
            case .forever: "Forever"
            }
        }
        var duration: TimeInterval? {
            switch self {
            case .week: 7 * 86_400
            case .month: 30 * 86_400
            case .quarter: 91 * 86_400
            case .forever: nil
            }
        }
    }

    var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            preferences.set(isEnabled, forKey: "historyEnabled")
            if isEnabled {
                load()
                onEnabled?()
            } else {
                // Saved shots stay on disk until cleared; they are just not shown.
                entries = []
                savedShelf = nil
                thumbnails.removeAllObjects()
            }
        }
    }
    var retention: Retention {
        didSet {
            guard oldValue != retention else { return }
            preferences.set(retention.rawValue, forKey: "historyRetention")
            pruneExpired()
        }
    }
    var query = ""
    var showsPinnedOnly = false
    private(set) var entries: [ShotHistoryEntry] = []
    private(set) var storageBytes = 0
    private(set) var failure: String?

    var results: [ShotHistoryEntry] {
        let terms = ShotHistoryEntry.terms(in: query)
        return entries.filter { (!showsPinnedOnly || $0.isPinned) && $0.matches(terms) }
    }

    /// Lets the shelf add its current shots when history is turned on.
    @ObservationIgnored var onEnabled: (() -> Void)?

    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let archive: ShotArchive
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var shelf: [UUID] = []
    /// What shelf.json holds, once known.
    @ObservationIgnored private var savedShelf: [UUID]?
    @ObservationIgnored private let thumbnails = NSCache<NSUUID, NSImage>()

    init(preferences: UserDefaults, archive: ShotArchive, now: @escaping () -> Date = Date.init) {
        self.preferences = preferences
        self.archive = archive
        self.now = now
        isEnabled = preferences.object(forKey: "historyEnabled") as? Bool ?? false
        retention = preferences.string(forKey: "historyRetention").flatMap(Retention.init(rawValue:)) ?? .month
    }

    /// Reads saved shots and removes those past retention. With history off,
    /// only the space used is read, so leftover shots can still be deleted.
    func load() {
        enqueue { [weak self] archive in
            let bytes = await archive.storageBytes()
            guard let self else { return }
            self.storageBytes = bytes
            guard self.isEnabled else { return }
            let entries = await archive.entries()
            let savedShelf = await archive.shelf()
            guard self.isEnabled else { return }
            self.entries = entries
            self.savedShelf = savedShelf
            self.pruneExpired()
        }
    }

    func record(_ capture: CaptureResult) {
        guard isEnabled else { return }
        enqueue { [weak self] archive in
            do {
                let entry = try await archive.save(capture)
                let bytes = await archive.storageBytes()
                guard let self, self.isEnabled else { return }
                self.entries.removeAll { $0.id == entry.id }
                let index = self.entries.firstIndex { $0.capturedAt < entry.capturedAt } ?? self.entries.endIndex
                self.entries.insert(entry, at: index)
                self.storageBytes = bytes
                self.failure = nil
                self.pruneExpired()
            } catch {
                self?.failure = "Couldn’t save a shot to history: \(error.localizedDescription)"
            }
        }
    }

    func setPinned(_ pinned: Bool, for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isPinned = pinned
        enqueue { [weak self] archive in
            do {
                _ = try await archive.setPinned(pinned, for: id)
            } catch {
                self?.failure = "Couldn’t update that shot: \(error.localizedDescription)"
            }
        }
    }

    func delete(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        entries.removeAll { ids.contains($0.id) }
        ids.forEach { thumbnails.removeObject(forKey: $0 as NSUUID) }
        enqueue { [weak self] archive in
            for id in ids { try? await archive.delete(id) }
            let bytes = await archive.storageBytes()
            self?.storageBytes = bytes
        }
    }

    /// Deletes every saved shot, pinned or not. The shelf itself is untouched.
    func deleteAll() {
        entries = []
        thumbnails.removeAllObjects()
        enqueue { [weak self] archive in
            do {
                try await archive.deleteAll()
                guard let self else { return }
                self.savedShelf = nil
                self.storageBytes = 0
            } catch {
                self?.failure = "Couldn’t clear history: \(error.localizedDescription)"
            }
        }
    }

    /// Remembers the shelf's order so a relaunch can restore it. Bursts of
    /// changes coalesce into one write of the latest order.
    func rememberShelf(_ ids: [UUID]) {
        shelf = ids
        guard isEnabled else { return }
        enqueue { [weak self] archive in
            guard let self, self.isEnabled, self.savedShelf != self.shelf else { return }
            let ids = self.shelf
            do {
                try await archive.saveShelf(ids)
                self.savedShelf = ids
            } catch {
                self.failure = "Couldn’t remember the shelf: \(error.localizedDescription)"
            }
        }
    }

    /// Whether relaunching now would bring back exactly these shots.
    func holdsShelf(_ ids: [UUID]) -> Bool {
        guard isEnabled, savedShelf == ids else { return false }
        let saved = Set(entries.map(\.id))
        return ids.allSatisfy(saved.contains)
    }

    /// The previous session's shelf, in order. Shots deleted since are skipped.
    func restoreShelf() async -> [CaptureResult] {
        guard isEnabled else { return [] }
        return await enqueue { [weak self] archive in
            let ids = await archive.shelf()
            var captures: [CaptureResult] = []
            for id in ids {
                if let capture = try? await archive.capture(id) { captures.append(capture) }
            }
            self?.savedShelf = ids
            return captures
        }.value
    }

    func capture(for id: UUID) async throws -> CaptureResult {
        try await archive.capture(id)
    }

    func thumbnail(for id: UUID) async -> NSImage? {
        if let cached = thumbnails.object(forKey: id as NSUUID) { return cached }
        guard let data = await archive.thumbnail(id), let image = NSImage(data: data) else { return nil }
        thumbnails.setObject(image, forKey: id as NSUUID)
        return image
    }

    /// Waits for every queued save, pin, delete, and shelf update.
    func settle() async {
        await work?.value
    }

    /// Unpinned shots past retention go. Shots on the shelf, including one
    /// still waiting to be restored after a relaunch, stay until they leave it.
    private func pruneExpired() {
        guard isEnabled, let duration = retention.duration else { return }
        let cutoff = now().addingTimeInterval(-duration)
        let onShelf = Set(shelf).union(savedShelf ?? [])
        delete(entries.filter { !$0.isPinned && $0.capturedAt < cutoff && !onShelf.contains($0.id) }.map(\.id))
    }

    /// File work runs in order, one operation at a time, off the main thread.
    @discardableResult
    private func enqueue<Value>(_ operation: @escaping @MainActor (ShotArchive) async -> Value) -> Task<Value, Never> {
        let previous = work
        let archive = archive
        let task = Task { @MainActor in
            await previous?.value
            return await operation(archive)
        }
        work = Task { @MainActor in _ = await task.value }
        return task
    }
}
