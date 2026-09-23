// SPDX-License-Identifier: MIT
import Foundation

/// One saved shot as the history list and search see it. Screenshots and
/// trees stay on disk until the shot is opened.
struct ShotHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let capturedAt: Date
    let appName: String
    let bundleIdentifier: String
    let windowTitle: String
    let hasScreenshot: Bool
    let elementCount: Int
    var isPinned: Bool
    /// Case-, accent-, and width-folded text that queries match against.
    let searchText: String

    /// Bounds memory for very large trees; the first part of a window's text
    /// is what people search for.
    static let maximumSearchCharacters = 100_000

    init(capture: CaptureResult, isPinned: Bool = false) {
        id = capture.id
        capturedAt = capture.date
        appName = capture.appName
        bundleIdentifier = capture.bundleIdentifier
        windowTitle = capture.windowTitle
        hasScreenshot = capture.pngData != nil
        elementCount = capture.elementCount
        self.isPinned = isPinned
        let text = [capture.appName, capture.windowTitle, capture.accessibilityText, capture.ocrText, capture.importedText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        searchText = String(Self.fold(text).prefix(Self.maximumSearchCharacters))
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// The words of a query. Every one must appear, in any order.
    static func terms(in query: String) -> [String] {
        fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    func matches(_ terms: [String]) -> Bool {
        terms.allSatisfy { searchText.range(of: $0) != nil }
    }
}

/// The on-disk form of a shot apart from its screenshot. Window placement is
/// runtime presentation only and is not kept.
struct StoredCapture: Codable, Equatable {
    static let currentSchema = 1

    let schema: Int
    let id: UUID
    let date: Date
    let appName: String
    let bundleIdentifier: String
    let windowTitle: String
    let windowID: UInt32?
    let axTree: [AXNode]
    let accessibilityText: String
    let ocrText: String
    let importedText: String
    let warnings: [String]
    let accessibilityTreeIncomplete: Bool

    init(_ capture: CaptureResult) {
        schema = Self.currentSchema
        id = capture.id
        date = capture.date
        appName = capture.appName
        bundleIdentifier = capture.bundleIdentifier
        windowTitle = capture.windowTitle
        windowID = capture.windowID
        axTree = capture.axTree
        accessibilityText = capture.accessibilityText
        ocrText = capture.ocrText
        importedText = capture.importedText
        warnings = capture.warnings
        accessibilityTreeIncomplete = capture.accessibilityTreeIncomplete
    }

    func capture(pngData: Data?) -> CaptureResult {
        CaptureResult(id: id, date: date, appName: appName, bundleIdentifier: bundleIdentifier, windowTitle: windowTitle,
                      windowID: windowID, pngData: pngData, axTree: axTree, accessibilityText: accessibilityText,
                      ocrText: ocrText, importedText: importedText, warnings: warnings,
                      accessibilityTreeIncomplete: accessibilityTreeIncomplete)
    }
}
