// SPDX-License-Identifier: MIT
import AppKit
import XCTest

extension XCTestCase {
    /// A private defaults suite and pasteboard for one store under test, both
    /// released at teardown, so no test reads or writes the real ones.
    @MainActor
    func isolatedStoreDependencies(_ label: String = #function) -> (preferences: UserDefaults, clipboard: NSPasteboard) {
        let name = "NotchShotTests.\(label).\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let clipboard = NSPasteboard(name: .init(name))
        addTeardownBlock {
            preferences.removePersistentDomain(forName: name)
            clipboard.releaseGlobally()
        }
        return (preferences, clipboard)
    }
}

enum TestEnvironment {
    /// GitHub Actions sets CI=true. A few native panel checks only run locally.
    static var isContinuousIntegration: Bool { ProcessInfo.processInfo.environment["CI"] == "true" }
}
