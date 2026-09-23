// SPDX-License-Identifier: MIT
import Foundation

struct CaptureTarget: Sendable {
    let pid: Int32
    let appName: String
    let bundleIdentifier: String
}

struct AXNode: Codable, Equatable, Identifiable, Sendable {
    var id: Int
    var role: String
    var roleDescription: String
    var title: String = ""
    var value: String = ""
    var elementDescription: String = ""
    var help: String = ""
    var url: String = ""
    var placeholder: String = ""
    var isSettable: Bool = false
    var isProtected: Bool = false
    var children: [AXNode] = []

    var label: String {
        var result = roleDescription.isEmpty ? role : roleDescription
        if isSettable { result += " (settable)" }
        if isProtected { return result + " [protected]" }
        let name = title.isEmpty ? elementDescription : title
        if !name.isEmpty { result += " " + name }
        if !value.isEmpty && value != name { result += ", Value: " + value }
        if !url.isEmpty && url != value { result += ", URL: " + url }
        if !placeholder.isEmpty { result += ", Placeholder: " + placeholder }
        if !help.isEmpty && help != name { result += ", Help: " + help }
        return result
    }

    func formatted(depth: Int = 0) -> String {
        let indentation = String(repeating: "\t", count: depth)
        let line = indentation + label.replacingOccurrences(of: "\n", with: "\n" + indentation + "  ")
        return ([line] + children.map { $0.formatted(depth: depth + 1) }).joined(separator: "\n")
    }

    var descendantCount: Int { 1 + children.reduce(0) { $0 + $1.descendantCount } }
}

struct CaptureResult: Identifiable, Sendable {
    var id = UUID()
    var date = Date()
    var appName: String
    var bundleIdentifier: String
    var windowTitle: String
    var windowID: UInt32?
    /// Global screen coordinates with the origin at the main display's top
    /// left, as reported by CGWindow and SCWindow. Runtime presentation only.
    var sourceWindowFrame: CGRect? = nil
    var pngData: Data?
    var axTree: [AXNode] = []
    var accessibilityText = ""
    var ocrText = ""
    var importedText = ""
    var warnings: [String] = []
    var accessibilityTreeIncomplete = false

    var elementCount: Int { axTree.reduce(0) { $0 + $1.descendantCount } }
    var treeText: String {
        "Window: \"\(windowTitle)\", App: \(appName).\n" + axTree.map { $0.formatted() }.joined(separator: "\n")
    }
    var clipboardTreeNotice: String {
        guard accessibilityTreeIncomplete, !axTree.isEmpty else { return "" }
        return "[Accessibility tree is incomplete: some content was unavailable, omitted, or truncated during capture.]\n"
    }
    /// Clipboard context follows the captured hierarchy. Other text sources
    /// remain available in the viewer and exports, but are never substituted
    /// for an accessibility tree without the receiving app knowing.
    var clipboardText: String {
        guard !axTree.isEmpty else {
            return treeText + "No accessibility tree was available for this shot."
        }
        return clipboardTreeNotice + treeText
    }
    var readableText: String {
        if !accessibilityText.isEmpty { return accessibilityText }
        return importedText.isEmpty ? ocrText : importedText
    }
    var contextText: String {
        var sections = ["# Appshot — \(appName)", "Window: \(windowTitle)", "Captured: \(date.ISO8601Format())"]
        if !accessibilityText.isEmpty { sections.append("## Accessibility text\n\(accessibilityText)") }
        if !ocrText.isEmpty { sections.append("## Text recognized from screenshot (OCR)\n\(ocrText)") }
        if !importedText.isEmpty { sections.append("## Imported text\n\(importedText)") }
        if !axTree.isEmpty { sections.append("## Accessibility tree\n\(treeText)") }
        if !warnings.isEmpty { sections.append("## Capture notes\n" + warnings.map { "- " + $0 }.joined(separator: "\n")) }
        return sections.joined(separator: "\n\n")
    }
}
