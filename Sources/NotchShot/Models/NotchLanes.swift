// SPDX-License-Identifier: MIT
import Foundation

/// What sits left of the hardware notch. Raw values are saved preference keys.
enum NotchMark: String, CaseIterable, Identifiable, Sendable {
    case aperture
    case viewfinder
    case camera
    case none

    var id: Self { self }

    var name: String {
        switch self {
        case .aperture: "Aperture"
        case .viewfinder: "Viewfinder"
        case .camera: "Camera"
        case .none: "None"
        }
    }
}

/// What sits right of the notch when nothing more urgent needs showing.
enum NotchIndicator: String, CaseIterable, Identifiable, Sendable {
    case shotCount
    case statusDot
    case none

    var id: Self { self }

    var name: String {
        switch self {
        case .shotCount: "Shot count"
        case .statusDot: "Status dot"
        case .none: "None"
        }
    }

    enum Content: Equatable {
        case progress
        case count(Int)
        case dot(ready: Bool)
        case nothing
    }

    /// Capture progress and missing permissions always show, whatever the
    /// choice: without them a capture could fail with no sign in the notch.
    func content(isCapturing: Bool, shotCount: Int, permissionsReady: Bool) -> Content {
        if isCapturing { return .progress }
        if !permissionsReady { return .dot(ready: false) }
        switch self {
        case .shotCount: return shotCount > 0 ? .count(shotCount) : .dot(ready: true)
        case .statusDot: return .dot(ready: true)
        case .none: return .nothing
        }
    }
}
