// SPDX-License-Identifier: MIT
import Foundation

/// A dated event keeps feedback brief without replaying it on page changes.
struct StatusNotice: Identifiable, Equatable {
    enum Kind: Equatable { case success, info, error }

    let id = UUID()
    let message: String
    let title: String
    let kind: Kind
    let createdAt: Date
    let expiresAt: Date
    let revealURL: URL?

    init(message: String, kind: Kind? = nil, revealURL: URL? = nil, createdAt: Date = Date()) {
        self.message = message
        self.createdAt = createdAt
        self.revealURL = revealURL
        let summary = Self.summary(for: message)
        self.kind = kind ?? summary.kind
        self.title = self.kind == .error ? "Needs attention" : summary.title
        let lifetime: TimeInterval
        switch self.kind {
        case .success: lifetime = 3
        case .info: lifetime = 5
        case .error: lifetime = 8
        }
        expiresAt = createdAt.addingTimeInterval(lifetime)
    }

    func remainingDuration(at date: Date) -> TimeInterval {
        max(0, expiresAt.timeIntervalSince(date))
    }

    func isExpired(at date: Date) -> Bool { date >= expiresAt }

    private static func summary(for message: String) -> (title: String, kind: Kind) {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("could not ") || text.hasPrefix("export failed:") || text.contains(" is unavailable.") {
            return ("Needs attention", .error)
        }
        if text.hasPrefix("exported to ") { return ("Exported", .success) }
        if text.hasSuffix(" copied.") || text.hasPrefix("text copied ") || text.hasPrefix("shot copied.") || text.hasSuffix(" · copied") {
            return ("Copied", .success)
        }
        if text.hasPrefix("removed ") { return ("Removed", .success) }
        if text == "session captures cleared." { return ("Cleared", .success) }
        if text.hasPrefix("captured ") { return ("Captured", .success) }
        if text.hasPrefix("added ") { return ("Added", .success) }
        if text.hasPrefix("capture shortcut set to ") { return ("Shortcut saved", .success) }
        if text.hasPrefix("adding ") { return ("Adding…", .info) }
        if text.hasPrefix("enable the permissions") { return ("Set up capture", .info) }
        if text.hasPrefix("open an app window") { return ("Open an app", .info) }
        return ("Notice", .info)
    }
}
