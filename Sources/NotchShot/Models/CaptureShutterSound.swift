// SPDX-License-Identifier: MIT
import Foundation

enum CaptureShutterSound: String, CaseIterable, Identifiable {
    case xt3 = "fujifilm-xt3"
    case x100s = "fujifilm-x100s"
    case finepixF11 = "fujifilm-finepix-f11"

    static let defaultSound: CaptureShutterSound = .xt3

    var id: String { rawValue }

    var title: String {
        switch self {
        case .xt3: "Fujifilm X-T3"
        case .x100s: "Fujifilm X100S"
        case .finepixF11: "Fujifilm FinePix F11"
        }
    }

    var resourceName: String {
        switch self {
        case .xt3: "CaptureShutter"
        case .x100s: "CaptureShutterX100S"
        case .finepixF11: "CaptureShutterFinePixF11"
        }
    }

    var shortTitle: String {
        switch self {
        case .xt3: "X-T3"
        case .x100s: "X100S"
        case .finepixF11: "F11"
        }
    }

    var familyTitle: String {
        switch self {
        case .xt3, .x100s: "FUJIFILM"
        case .finepixF11: "FINEPIX"
        }
    }

    var cameraIconResourceName: String {
        switch self {
        case .xt3: "CameraXT3"
        case .x100s: "CameraX100S"
        case .finepixF11: "CameraFinePixF11"
        }
    }

    var cameraIconURL: URL? {
        if let url = Bundle.main.url(forResource: cameraIconResourceName, withExtension: "png") {
            return url
        }
        // Packaged apps carry the icons directly. A missing optional icon must
        // not evaluate SwiftPM's generated bundle accessor, which can fatalError
        // when the development resource bundle is absent on another Mac.
        guard Bundle.main.bundleURL.pathExtension != "app" else { return nil }
        return Bundle.module.url(forResource: cameraIconResourceName, withExtension: "png")
    }

    /// Installed apps own these files directly. SwiftPM's bundle supports
    /// development and tests without being required by the installed app.
    var resourceURL: URL? {
        Bundle.main.url(forResource: resourceName, withExtension: "wav")
            ?? Bundle.module.url(forResource: resourceName, withExtension: "wav")
    }
}
