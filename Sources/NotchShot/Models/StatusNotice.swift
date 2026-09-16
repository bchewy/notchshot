// SPDX-License-Identifier: MIT
import Foundation

/// A dated event keeps feedback brief without replaying it on page changes.
/// The producer names the kind and title; nothing is inferred from wording.
struct StatusNotice: Identifiable, Equatable {
    enum Kind: Equatable {
        case success, info, error

        var lifetime: TimeInterval {
            switch self {
            case .success: return 3
            case .info: return 5
            case .error: return 8
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let message: String
    let createdAt: Date
    let expiresAt: Date
    let revealURL: URL?

    init(kind: Kind, title: String, message: String, revealURL: URL? = nil, createdAt: Date = Date()) {
        self.kind = kind
        self.title = title
        self.message = message
        self.revealURL = revealURL
        self.createdAt = createdAt
        expiresAt = createdAt.addingTimeInterval(kind.lifetime)
    }

    func remainingDuration(at date: Date) -> TimeInterval {
        max(0, expiresAt.timeIntervalSince(date))
    }

    func isExpired(at date: Date) -> Bool { date >= expiresAt }
}
