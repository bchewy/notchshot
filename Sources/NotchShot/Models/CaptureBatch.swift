// SPDX-License-Identifier: MIT
import Foundation

enum BatchContextStyle: String, CaseIterable, Identifiable, Sendable {
    case compact
    case full

    var id: String { rawValue }
    var label: String { self == .compact ? "Compact" : "Full" }
    var help: String {
        switch self {
        case .compact:
            return "Keep the main text, useful controls, and capture notes. Repeated lines and omitted or shortened content are marked. Originals stay unchanged."
        case .full:
            return "Include every shot’s complete text, OCR, accessibility tree, and capture notes."
        }
    }
}

/// A copy-time snapshot. Text reduction is explicit and local; screenshots and
/// the source captures are never modified. The shelf supplies at most eight shots.
struct CaptureBatch: Sendable {
    static let maximumCompactCharacters = 32_000
    static let maximumCompactCharactersPerShot = 6_000

    let captures: [CaptureResult]
    let contextStyle: BatchContextStyle
    let contextText: String
    let originalCharacterCount: Int
    let characterCount: Int
    let isShortened: Bool
    let removedDuplicateLines: Int
    let unavailableImageIDs: Set<UUID>

    var omittedScreenshotNumbers: [Int] {
        captures.enumerated().compactMap { unavailableImageIDs.contains($0.element.id) ? $0.offset + 1 : nil }
    }

    /// Original bytes, in shot order. The clipboard service validates images.
    var imagePNGs: [Data] { captures.filter { !unavailableImageIDs.contains($0.id) }.compactMap(\.pngData) }

    init(captures: [CaptureResult], contextStyle: BatchContextStyle,
         unavailableImageIDs: Set<UUID> = []) {
        var seen = Set<UUID>()
        let orderedCaptures = captures.filter { seen.insert($0.id).inserted }
        self.captures = orderedCaptures
        self.contextStyle = contextStyle
        let unavailable = unavailableImageIDs.intersection(orderedCaptures.filter { $0.pngData != nil }.map(\.id))
        self.unavailableImageIDs = unavailable
        guard contextStyle == .compact, !orderedCaptures.isEmpty else {
            let full = Self.fullText(orderedCaptures, unavailableImageIDs: unavailable)
            originalCharacterCount = full.count
            contextText = full
            characterCount = full.count
            isShortened = false
            removedDuplicateLines = 0
            return
        }

        // Count source pieces without allocating the complete, potentially
        // multi-megabyte context just to discard it in Compact mode.
        originalCharacterCount = Self.fullCharacterCount(orderedCaptures, unavailableImageIDs: unavailable)

        let header = "# NotchShot — \(orderedCaptures.count) shots · Compact context\n\nLocally prepared excerpts. Any omitted or shortened content is marked; full originals remain in NotchShot."
        let separator = "\n\n"
        let bodyBudget = Self.maximumCompactCharacters - header.count - separator.count * orderedCaptures.count
        let perShotBudget = min(Self.maximumCompactCharactersPerShot, max(0, bodyBudget / orderedCaptures.count))
        let excerpts = orderedCaptures.enumerated().map {
            Self.compactShot($0.element, index: $0.offset + 1,
                             total: orderedCaptures.count, budget: perShotBudget,
                             unavailableImageIDs: unavailable)
        }
        contextText = ([header] + excerpts.map(\.text)).joined(separator: separator)
        characterCount = contextText.count
        isShortened = excerpts.contains(where: \.isShortened)
        removedDuplicateLines = excerpts.reduce(0) { $0 + $1.removedDuplicateLines }
    }

    private struct Excerpt {
        var text: String
        var isShortened: Bool
        var removedDuplicateLines: Int = 0
        var didStopExamining: Bool = false
    }

    private static func boundary(index: Int, total: Int) -> String {
        "--- Shot \(index) of \(total) ---"
    }

    private static func screenshotNote(_ capture: CaptureResult, index: Int,
                                       unavailableImageIDs: Set<UUID>) -> String {
        if unavailableImageIDs.contains(capture.id) { return "Screenshot: unavailable; text retained." }
        return capture.pngData == nil ? "Screenshot: none captured."
            : "Screenshot source: Shot \(index)."
    }

    private static func fullText(_ captures: [CaptureResult], unavailableImageIDs: Set<UUID>) -> String {
        guard !captures.isEmpty else { return "" }
        let sections = captures.enumerated().map {
            boundary(index: $0.offset + 1, total: captures.count) + "\n"
                + screenshotNote($0.element, index: $0.offset + 1, unavailableImageIDs: unavailableImageIDs)
                + "\n\n" + $0.element.contextText
        }
        return (["# NotchShot — \(captures.count) shots · Full context"] + sections).joined(separator: "\n\n")
    }

    /// Counts exactly the pieces used by CaptureResult.contextText, including
    /// tree indentation, without materializing a second complete context string.
    private static func fullCharacterCount(_ captures: [CaptureResult], unavailableImageIDs: Set<UUID>) -> Int {
        guard !captures.isEmpty else { return 0 }
        var counter = CharacterCounter()
        counter.append("# NotchShot — \(captures.count) shots · Full context")
        for (index, capture) in captures.enumerated() {
            counter.append("\n\n" + boundary(index: index + 1, total: captures.count) + "\n")
            counter.append(screenshotNote(capture, index: index + 1, unavailableImageIDs: unavailableImageIDs))
            counter.append("\n\n# Appshot — ")
            counter.append(capture.appName)
            counter.append("\n\nWindow: ")
            counter.append(capture.windowTitle)
            counter.append("\n\nCaptured: " + capture.date.ISO8601Format())
            for (heading, text) in [
                ("Accessibility text", capture.accessibilityText),
                ("Text recognized from screenshot (OCR)", capture.ocrText),
                ("Imported text", capture.importedText)
            ] where !text.isEmpty {
                counter.append("\n\n## " + heading + "\n")
                counter.append(text)
            }
            if !capture.axTree.isEmpty {
                counter.append("\n\n## Accessibility tree\nWindow: \"")
                counter.append(capture.windowTitle)
                counter.append("\", App: ")
                counter.append(capture.appName)
                counter.append(".\n")
                var stack = capture.axTree.reversed().map { (node: $0, depth: 0) }
                var first = true
                while let (node, depth) = stack.popLast() {
                    if !first { counter.append("\n") }
                    first = false
                    let indentation = String(repeating: "\t", count: depth)
                    counter.append(indentation)
                    for part in labelParts(node) {
                        var start = part.startIndex
                        while let newline = part.range(of: "\n", options: .literal, range: start..<part.endIndex) {
                            counter.append(part[start..<newline.lowerBound])
                            counter.append("\n" + indentation + "  ")
                            start = newline.upperBound
                        }
                        counter.append(part[start...])
                    }
                    stack.append(contentsOf: node.children.reversed().map { ($0, depth + 1) })
                }
            }
            if !capture.warnings.isEmpty {
                counter.append("\n\n## Capture notes\n")
                for (index, warning) in capture.warnings.enumerated() {
                    counter.append(index == 0 ? "- " : "\n- ")
                    counter.append(warning)
                }
            }
        }
        return counter.count
    }

    private static func labelParts(_ node: AXNode) -> [String] {
        var parts = [node.roleDescription.isEmpty ? node.role : node.roleDescription]
        if node.isSettable { parts.append(" (settable)") }
        if node.isProtected { return parts + [" [protected]"] }
        let name = node.title.isEmpty ? node.elementDescription : node.title
        if !name.isEmpty { parts += [" ", name] }
        if !node.value.isEmpty && node.value != name { parts += [", Value: ", node.value] }
        if !node.url.isEmpty && node.url != node.value { parts += [", URL: ", node.url] }
        if !node.placeholder.isEmpty { parts += [", Placeholder: ", node.placeholder] }
        if !node.help.isEmpty && node.help != name { parts += [", Help: ", node.help] }
        return parts
    }

    /// Source fields are separated by literal ASCII punctuation or newlines.
    /// Account for a leading combining mark or a CR/LF at those boundaries.
    private struct CharacterCounter {
        var count = 0
        private var last: Character?

        mutating func append<S: StringProtocol>(_ part: S) {
            guard let first = part.first else { return }
            let partCount = part.count
            if let last {
                let boundary = String(last) + String(first)
                count += boundary.count - 2
                self.last = partCount == 1 ? boundary.last : part.last
            } else {
                last = part.last
            }
            count += partCount
        }
    }

    private static func compactShot(_ capture: CaptureResult, index: Int,
                                    total: Int, budget: Int, unavailableImageIDs: Set<UUID>) -> Excerpt {
        let app = clipped(capture.appName, limit: 180, marker: "…")
        let title = clipped(capture.windowTitle, limit: 280, marker: "…")
        var shortened = app.isShortened || title.isShortened
        let metadata = "\(boundary(index: index, total: total))\n\(screenshotNote(capture, index: index, unavailableImageIDs: unavailableImageIDs))\nApp: \(app.text)\nWindow: \(title.text)\nCaptured: \(capture.date.ISO8601Format())"
        // The same priority used by CaptureResult.readableText. Other sources
        // are explicitly named, never silently merged into this source.
        let sources: [(name: String, text: String)] = [
            ("Accessibility text", capture.accessibilityText),
            ("Imported text", capture.importedText),
            ("Text recognized from screenshot (OCR)", capture.ocrText)
        ].filter { !$0.text.isEmpty }
        let source = sources.first
        let deduplicated = deduplicatingLines(source?.text ?? "", inputLimit: min(24_000, budget * 4))
        shortened = shortened || deduplicated.isShortened

        var trailing: [String] = []
        if deduplicated.didStopExamining {
            trailing.append("[Remaining source not examined in compact context; full text retained in NotchShot.]")
        }
        if sources.count > 1 {
            trailing.append("[Additional sources omitted in compact context: \(sources.dropFirst().map(\.name).joined(separator: ", ")). Full sources retained in NotchShot.]")
            shortened = true
        }
        if !capture.axTree.isEmpty {
            trailing.append(controlsSummary(capture.axTree, limit: min(650, budget / 5)))
            shortened = true // Even a complete control list omits tree hierarchy.
        }
        if !capture.warnings.isEmpty {
            let warnings = compactWarnings(capture.warnings, limit: min(600, budget / 5))
            trailing.append("Capture notes:\n" + warnings.text)
            shortened = shortened || warnings.isShortened
        }

        var sections = [metadata]
        if let source {
            let heading = "\(source.name):\n"
            let repeatedLineLabel = deduplicated.removedDuplicateLines == 1 ? "line" : "lines"
            let duplicateNotice = deduplicated.removedDuplicateLines > 0
                ? "\n[Removed \(deduplicated.removedDuplicateLines) repeated \(repeatedLineLabel) within this source.]" : ""
            let fixedCount = metadata.count + trailing.reduce(0) { $0 + $1.count }
            let separatorCount = (trailing.count + 1) * 2
            let available = max(0, budget - fixedCount - separatorCount - heading.count - duplicateNotice.count)
            let readable = clipped(deduplicated.text, limit: available,
                                   marker: "\n[Text shortened to fit compact context; full text retained in NotchShot.]")
            sections.append(heading + readable.text + duplicateNotice)
            shortened = shortened || readable.isShortened
        } else {
            sections.append("No readable text was captured.")
        }
        sections += trailing
        let assembled = sections.joined(separator: "\n\n")
        // Also bound metadata-only shots and pathological imported fields. The
        // final marker survives clipping, rather than losing the disclosure.
        let bounded = clipped(assembled, limit: budget,
                              marker: "\n[Shot excerpt shortened; full capture retained in NotchShot.]")
        return Excerpt(text: bounded.text, isShortened: shortened || bounded.isShortened,
                       removedDuplicateLines: deduplicated.removedDuplicateLines)
    }

    private static func deduplicatingLines(_ text: String, inputLimit: Int) -> Excerpt {
        let end = text.index(text.startIndex, offsetBy: max(0, inputLimit), limitedBy: text.endIndex) ?? text.endIndex
        let stopped = end != text.endIndex
        var seen = Set<String>()
        var result: [String] = []
        var removed = 0
        for line in text[..<end].split(separator: "\n", omittingEmptySubsequences: false) {
            let comparison = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            // Repeated short labels, numbers, and blank lines often convey
            // structure. Only substantial repeated lines qualify for removal.
            if comparison.count >= 24, comparison.contains(where: \.isLetter) {
                guard seen.insert(comparison).inserted else { removed += 1; continue }
            }
            result.append(String(line))
        }
        return Excerpt(text: result.joined(separator: "\n"), isShortened: removed > 0 || stopped,
                       removedDuplicateLines: removed, didStopExamining: stopped)
    }

    private static func compactWarnings(_ warnings: [String], limit: Int) -> Excerpt {
        var text = ""
        for warning in warnings {
            if !text.isEmpty { text += "\n" }
            text += "- "
            text += warning.prefix(max(0, limit + 1 - text.count))
            if text.count > limit { break }
        }
        return clipped(text, limit: limit,
                       marker: "\n[Capture notes shortened; full notes retained in NotchShot.]")
    }

    private static func controlsSummary(_ roots: [AXNode], limit: Int) -> String {
        let roles: Set<String> = ["AXButton", "AXLink", "AXCheckBox", "AXRadioButton",
                                  "AXTextField", "AXTextArea", "AXPopUpButton", "AXComboBox",
                                  "AXMenuButton", "AXSlider", "AXTab", "AXDisclosureTriangle"]
        var stack = Array(roots.reversed())
        var lines: [String] = []
        var length = 0
        while let node = stack.popLast() {
            if roles.contains(node.role) || !node.url.isEmpty {
                let label: String
                if node.isProtected {
                    label = (node.roleDescription.isEmpty ? node.role : node.roleDescription) + " [protected]"
                } else {
                    let role = clipped(node.roleDescription.isEmpty ? node.role : node.roleDescription,
                                       limit: 40, marker: "…").text
                    let name = clipped(node.title.isEmpty ? node.elementDescription : node.title,
                                       limit: 100, marker: "…").text
                    let url = clipped(node.url, limit: 180, marker: "…").text
                    let value = clipped(node.value, limit: 90, marker: "…").text
                    label = role + (node.isSettable ? " (settable)" : "")
                        + (name.isEmpty ? "" : ": " + name)
                        + (value.isEmpty || value == name ? "" : ", Value: " + value)
                        + (url.isEmpty || url == value ? "" : " — " + url)
                }
                lines.append("- " + label)
                length += label.count + 3
                if length >= limit { break }
            }
            stack.append(contentsOf: node.children.reversed())
        }
        let heading = "Accessibility controls and links (partial; full tree retained):\n"
        guard !lines.isEmpty else {
            return "[Accessibility tree omitted: no controls or links to list. Full tree retained in NotchShot.]"
        }
        let body = clipped(lines.joined(separator: "\n"), limit: max(0, limit - heading.count),
                           marker: "\n[… more controls or links omitted.]")
        return heading + body.text
    }

    private static func clipped(_ text: String, limit: Int, marker: String) -> Excerpt {
        let safeLimit = max(0, limit)
        guard let end = text.index(text.startIndex, offsetBy: safeLimit, limitedBy: text.endIndex),
              end != text.endIndex else { return Excerpt(text: text, isShortened: false) }
        let suffix = String(marker.prefix(safeLimit))
        return Excerpt(text: String(text.prefix(max(0, safeLimit - suffix.count))) + suffix,
                       isShortened: true)
    }
}
