// SPDX-License-Identifier: MIT
import Foundation

enum ExportService {
    struct Metadata: Encodable {
        let schemaVersion = 1
        let capturedAt: Date
        let appName: String
        let bundleIdentifier: String
        let windowTitle: String
        let windowID: UInt32?
        let screenshotAvailable: Bool
        let accessibilityElementCount: Int
        let warnings: [String]
    }

    /// Creates one unique subfolder. Existing exports are never overwritten.
    static func export(_ capture: CaptureResult, to directory: URL) throws -> URL {
        let stamp = capture.date.ISO8601Format().replacingOccurrences(of: ":", with: "-")
        let folder = directory.appendingPathComponent("NotchShot-\(stamp)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        do {
            if let png = capture.pngData { try png.write(to: folder.appendingPathComponent("screenshot.png"), options: .atomic) }
            try capture.contextText.write(to: folder.appendingPathComponent("context.md"), atomically: true, encoding: .utf8)
            try capture.accessibilityText.write(to: folder.appendingPathComponent("accessibility.txt"), atomically: true, encoding: .utf8)
            try capture.treeText.write(to: folder.appendingPathComponent("accessibility-tree.txt"), atomically: true, encoding: .utf8)
            if !capture.ocrText.isEmpty { try capture.ocrText.write(to: folder.appendingPathComponent("ocr.txt"), atomically: true, encoding: .utf8) }
            if !capture.importedText.isEmpty { try capture.importedText.write(to: folder.appendingPathComponent("imported-text.txt"), atomically: true, encoding: .utf8) }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(capture.axTree).write(to: folder.appendingPathComponent("accessibility-tree.json"), options: .atomic)
            let metadata = Metadata(capturedAt: capture.date, appName: capture.appName, bundleIdentifier: capture.bundleIdentifier, windowTitle: capture.windowTitle, windowID: capture.windowID, screenshotAvailable: capture.pngData != nil, accessibilityElementCount: capture.elementCount, warnings: capture.warnings)
            try encoder.encode(metadata).write(to: folder.appendingPathComponent("metadata.json"), options: .atomic)
            return folder
        } catch {
            // Roll back only the new folder created by this invocation.
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }
}
