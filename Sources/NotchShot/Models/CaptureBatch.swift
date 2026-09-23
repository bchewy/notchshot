// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

enum BatchContextStyle: String, CaseIterable, Identifiable, Sendable {
    case compact
    case full

    var id: String { rawValue }
    var label: String { self == .compact ? "Compact" : "Full" }
    var help: String {
        switch self {
        case .compact:
            return "Keep a bounded excerpt of each accessibility tree, preserving its order and indentation. Shortened trees are marked; originals stay unchanged."
        case .full:
            return "Include every shot’s complete accessibility tree with its app and window name."
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
    /// A digest of the style, text, shot order, and every shot's PNG bytes.
    /// The clipboard item carries it so assisted paste can prove the item is
    /// this batch without hashing the images again on the main actor.
    let identity: String

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
            identity = Self.identity(style: contextStyle, contextText: full, captures: orderedCaptures)
            return
        }

        // Count source pieces without allocating the complete, potentially
        // multi-megabyte context just to discard it in Compact mode.
        originalCharacterCount = Self.fullCharacterCount(orderedCaptures, unavailableImageIDs: unavailable)

        let header = "# NotchShot — \(orderedCaptures.count) shots · Compact context\n\(CapturedContext.opening)\n\nAccessibility-tree excerpts. Any shortened content is marked; full trees remain in NotchShot."
        let separator = "\n\n"
        let bodyBudget = Self.maximumCompactCharacters - header.count - CapturedContext.closing.count
            - separator.count * (orderedCaptures.count + 1)
        let perShotBudget = min(Self.maximumCompactCharactersPerShot, max(0, bodyBudget / orderedCaptures.count))
        let excerpts = orderedCaptures.enumerated().map {
            Self.compactShot($0.element, index: $0.offset + 1,
                             total: orderedCaptures.count, budget: perShotBudget,
                             unavailableImageIDs: unavailable)
        }
        contextText = ([header] + excerpts.map(\.text) + [CapturedContext.closing]).joined(separator: separator)
        characterCount = contextText.count
        isShortened = excerpts.contains(where: \.isShortened)
        removedDuplicateLines = 0
        identity = Self.identity(style: contextStyle, contextText: contextText, captures: orderedCaptures)
    }

    private static func identity(style: BatchContextStyle, contextText: String, captures: [CaptureResult]) -> String {
        var digest = SHA256()
        func append(_ bytes: Data) {
            var length = UInt64(bytes.count).bigEndian
            withUnsafeBytes(of: &length) { digest.update(data: Data($0)) }
            digest.update(data: bytes)
        }
        append(Data("NotchShot batch v1".utf8))
        append(Data(style.rawValue.utf8))
        append(Data(contextText.utf8))
        for capture in captures {
            append(Data(capture.id.uuidString.utf8))
            append(capture.pngData ?? Data())
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private struct Excerpt {
        var text: String
        var isShortened: Bool
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
                + "\n\n" + $0.element.clipboardBody
        }
        return (["# NotchShot — \(captures.count) shots · Full context\n" + CapturedContext.opening]
                + sections + [CapturedContext.closing]).joined(separator: "\n\n")
    }

    /// Counts exactly the clipboard payload, including indentation and Unicode
    /// boundaries, without allocating every full tree in Compact mode.
    private static func fullCharacterCount(_ captures: [CaptureResult], unavailableImageIDs: Set<UUID>) -> Int {
        guard !captures.isEmpty else { return 0 }
        var counter = CharacterCounter()
        counter.append("# NotchShot — \(captures.count) shots · Full context\n" + CapturedContext.opening)
        for (index, capture) in captures.enumerated() {
            counter.append("\n\n" + boundary(index: index + 1, total: captures.count) + "\n")
            counter.append(screenshotNote(capture, index: index + 1, unavailableImageIDs: unavailableImageIDs))
            counter.append("\n\n")
            counter.append(capture.clipboardTreeNotice)
            counter.append("Window: \"")
            counter.append(capture.windowTitle)
            counter.append("\", App: ")
            counter.append(capture.appName)
            counter.append(".\n")
            let nodes = AXNode.clipboardTree(capture.axTree)
            if nodes.isEmpty {
                counter.append("No accessibility tree was available for this shot.")
            } else {
                if AXNode.containsFrame(nodes) { counter.append(CapturedContext.positionsNote + "\n") }
                _ = visitTree(nodes) { part in
                    counter.append(part)
                    return true
                }
            }
        }
        counter.append("\n\n" + CapturedContext.closing)
        return counter.count
    }

    /// Emits the same depth-first, indented hierarchy as AXNode.formatted.
    /// Labels are streamed in pieces so one large AX value is never copied into
    /// a temporary complete label merely to keep a small prefix of it.
    @discardableResult
    private static func visitTree(_ roots: [AXNode], append: (Substring) -> Bool) -> Bool {
        var stack = roots.reversed().map { (node: $0, depth: 0) }
        var first = true
        while let (node, depth) = stack.popLast() {
            if !first, !append("\n") { return false }
            first = false
            let indentation = String(repeating: "\t", count: depth)
            guard append(indentation[...]) else { return false }
            for part in AXNode.labelParts(node) {
                var start = part.startIndex
                while let newline = part.range(of: "\n", options: .literal, range: start..<part.endIndex) {
                    guard append(part[start..<newline.lowerBound]),
                          append(("\n" + indentation + "  ")[...]) else { return false }
                    start = newline.upperBound
                }
                guard append(part[start...]) else { return false }
            }
            stack.append(contentsOf: node.children.reversed().map { ($0, depth + 1) })
        }
        return true
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

    /// Accumulates only enough characters to detect truncation. The extra two
    /// characters account for a combining mark joining the previous chunk.
    private struct BoundedText {
        let limit: Int
        var text = ""
        private var counter = CharacterCounter()

        init(limit: Int) { self.limit = max(0, limit) }

        mutating func append(_ part: Substring) -> Bool {
            let end = part.index(part.startIndex, offsetBy: max(0, limit - counter.count) + 2,
                                 limitedBy: part.endIndex) ?? part.endIndex
            let prefix = part[..<end]
            counter.append(prefix)
            text += prefix
            return counter.count <= limit && end == part.endIndex
        }
    }

    private static func compactShot(_ capture: CaptureResult, index: Int,
                                    total: Int, budget: Int, unavailableImageIDs: Set<UUID>) -> Excerpt {
        let app = clipped(capture.appName, limit: 180, marker: "…")
        let title = clipped(capture.windowTitle, limit: 280, marker: "…")
        let metadataShortened = app.isShortened || title.isShortened
        var metadata = "\(boundary(index: index, total: total))\n\(screenshotNote(capture, index: index, unavailableImageIDs: unavailableImageIDs))\n\n\(capture.clipboardTreeNotice)Window: \"\(title.text)\", App: \(app.text).\n"
        if metadataShortened {
            metadata += "[App or window name shortened; full names retained in NotchShot.]\n"
        }
        let nodes = AXNode.clipboardTree(capture.axTree)
        if AXNode.containsFrame(nodes) { metadata += CapturedContext.positionsNote + "\n" }
        let treeBudget = max(0, budget - metadata.count)
        var tree = BoundedText(limit: treeBudget)
        if nodes.isEmpty {
            _ = tree.append("No accessibility tree was available for this shot.")
        } else {
            visitTree(nodes) { tree.append($0) }
        }
        let excerpt = clipped(tree.text, limit: treeBudget,
                              marker: "\n[Accessibility tree shortened to fit compact context; full tree retained in NotchShot.]")
        // Shelf batches contain at most eight shots. Keep a final bound for
        // unusually large programmatic batches or future metadata additions.
        let bounded = clipped(metadata + excerpt.text, limit: budget,
                              marker: "\n[Shot shortened; full capture retained in NotchShot.]")
        return Excerpt(text: bounded.text,
                       isShortened: metadataShortened || excerpt.isShortened || bounded.isShortened)
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
