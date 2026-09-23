// SPDX-License-Identifier: MIT
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Saved shots on disk: one folder per shot inside a folder only this user
/// can open. A shot appears complete or not at all.
actor ShotArchive {
    private enum File {
        static let entry = "entry.json"
        static let capture = "capture.json"
        static let screenshot = "screenshot.png"
        static let thumbnail = "thumbnail.png"
        static let shelf = "shelf.json"
    }

    private static let stagingPrefix = ".staging-"

    nonisolated let root: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(root: URL) {
        self.root = root
    }

    static func defaultRoot() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.bchewy.NotchShot", isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
    }

    /// Shots never change after capture, so a shot already saved is kept as is.
    func save(_ capture: CaptureResult) throws -> ShotHistoryEntry {
        try prepareRoot()
        let destination = folder(for: capture.id)
        if let existing = try? readEntry(in: destination) { return existing }
        let staging = root.appendingPathComponent(Self.stagingPrefix + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            let entry = ShotHistoryEntry(capture: capture)
            try encoder.encode(StoredCapture(capture)).write(to: staging.appendingPathComponent(File.capture))
            if let png = capture.pngData {
                try png.write(to: staging.appendingPathComponent(File.screenshot))
                try Self.thumbnail(from: png)?.write(to: staging.appendingPathComponent(File.thumbnail))
            }
            // Written last: a folder without an entry is never listed.
            try encoder.encode(entry).write(to: staging.appendingPathComponent(File.entry))
            try FileManager.default.moveItem(at: staging, to: destination)
            return entry
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    /// Every readable shot, newest first. Leftovers from an interrupted save
    /// are removed; unreadable folders are skipped.
    func entries() -> [ShotHistoryEntry] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return [] }
        var entries: [ShotHistoryEntry] = []
        for name in names {
            if name.hasPrefix(Self.stagingPrefix) {
                try? FileManager.default.removeItem(at: root.appendingPathComponent(name))
                continue
            }
            guard let id = UUID(uuidString: name), let entry = try? readEntry(in: folder(for: id)), entry.id == id else { continue }
            entries.append(entry)
        }
        return entries.sorted { $0.capturedAt > $1.capturedAt }
    }

    func capture(_ id: UUID) throws -> CaptureResult {
        let folder = folder(for: id)
        let stored = try decoder.decode(StoredCapture.self, from: Data(contentsOf: folder.appendingPathComponent(File.capture)))
        guard stored.id == id else { throw CocoaError(.fileReadCorruptFile) }
        return stored.capture(pngData: try? Data(contentsOf: folder.appendingPathComponent(File.screenshot)))
    }

    func thumbnail(_ id: UUID) -> Data? {
        try? Data(contentsOf: folder(for: id).appendingPathComponent(File.thumbnail))
    }

    func setPinned(_ pinned: Bool, for id: UUID) throws -> ShotHistoryEntry {
        let folder = folder(for: id)
        var entry = try readEntry(in: folder)
        entry.isPinned = pinned
        try encoder.encode(entry).write(to: folder.appendingPathComponent(File.entry), options: .atomic)
        return entry
    }

    func delete(_ id: UUID) throws {
        let folder = folder(for: id)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        try FileManager.default.removeItem(at: folder)
    }

    /// Removes every saved shot and the remembered shelf.
    func deleteAll() throws {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        try FileManager.default.removeItem(at: root)
    }

    func storageBytes() -> Int {
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total = 0
        for case let file as URL in files {
            total += (try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize ?? 0) ?? 0
        }
        return total
    }

    /// The shelf's shots, in order, so a relaunch can bring them back.
    func saveShelf(_ ids: [UUID]) throws {
        try prepareRoot()
        try encoder.encode(ids).write(to: root.appendingPathComponent(File.shelf), options: .atomic)
    }

    func shelf() -> [UUID] {
        guard let data = try? Data(contentsOf: root.appendingPathComponent(File.shelf)) else { return [] }
        return (try? decoder.decode([UUID].self, from: data)) ?? []
    }

    private func folder(for id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func readEntry(in folder: URL) throws -> ShotHistoryEntry {
        try decoder.decode(ShotHistoryEntry.self, from: Data(contentsOf: folder.appendingPathComponent(File.entry)))
    }

    /// Screenshots can show anything on screen, so only this user may open them.
    private func prepareRoot() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    }

    /// A small PNG for the history list, so browsing never decodes full screenshots.
    static func thumbnail(from png: Data, maximumPixels: Int = 320) -> Data? {
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceThumbnailMaxPixelSize: maximumPixels] as CFDictionary
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
