// SPDX-License-Identifier: MIT
import Foundation

/// The representations the user wants on the clipboard. This choice never
/// removes content from the original shot or changes what capture collects.
enum CaptureCopyContent: String, CaseIterable, Identifiable, Sendable {
    case screenshotAndTree
    case imageOnly
    case treeOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .screenshotAndTree: return "Screenshot + AX tree"
        case .imageOnly: return "Image only"
        case .treeOnly: return "AX tree only"
        }
    }

    var shortLabel: String {
        switch self {
        case .screenshotAndTree: return "Both"
        case .imageOnly: return "Image"
        case .treeOnly: return "AX tree"
        }
    }

    var help: String {
        switch self {
        case .screenshotAndTree:
            return "Copy the screenshot and its accessibility tree together."
        case .imageOnly:
            return "Copy screenshots without accessibility text."
        case .treeOnly:
            return "Copy accessibility trees as text, without screenshots."
        }
    }
}
