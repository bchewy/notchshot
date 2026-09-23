// SPDX-License-Identifier: MIT
import AppKit
import ApplicationServices
import Foundation

/// An AX element is an IPC reference, not an AppKit view. We retain the selected
/// window and only read it, on one background task, after this snapshot is made.
struct AccessibilityWindowSnapshot: @unchecked Sendable {
    let element: AXUIElement
    let title: String
    let bounds: CGRect?
}

struct AccessibilityReadResult: Sendable {
    var tree: [AXNode] = []
    var text = ""
    var warnings: [String] = []
}

enum AccessibilityReader {
    static let maximumNodes = 1_500
    static let maximumDepth = 40
    static let maximumSeconds = 6.0
    static let maximumCharacters = 250_000
    static let perCallTimeout: Float = 0.12

    /// Freeze the focused window before the capture's first suspension point.
    /// This performs only a few bounded reads; the full tree runs off the main actor.
    static func snapshotFocusedWindow(pid: Int32) -> AccessibilityWindowSnapshot? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, perCallTimeout)
        guard let rawWindow = copy(app, kAXFocusedWindowAttribute as CFString),
              CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else { return nil }
        let window = unsafeBitCast(rawWindow, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(window, perCallTimeout)
        // Check protected-state before reading even the window's title.
        let metadata = copyMany(window, [kAXRoleAttribute, kAXSubroleAttribute, protectedAttribute])
        let protected = string(metadata?[1]) == kAXSecureTextFieldSubrole || bool(metadata?[2])
            || metadata?.contains(where: unreadableSecurityAttribute) == true
        let title = protected || metadata == nil ? "" : string(copy(window, kAXTitleAttribute as CFString))
        var point = CGPoint.zero
        var size = CGSize.zero
        var bounds: CGRect?
        if let position = copy(window, kAXPositionAttribute as CFString),
           let dimension = copy(window, kAXSizeAttribute as CFString),
           CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(dimension) == AXValueGetTypeID(),
           AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
           AXValueGetValue(unsafeBitCast(dimension, to: AXValue.self), .cgSize, &size),
           size.width > 0, size.height > 0 {
            bounds = CGRect(origin: point, size: size)
        }
        return AccessibilityWindowSnapshot(element: window, title: title, bounds: bounds)
    }

    static func read(window: AccessibilityWindowSnapshot) async throws -> AccessibilityReadResult {
        try await CaptureWorker.run {
            let traversal = Traversal()
            let root = traversal.visit(window.element, depth: 0)
            try Task.checkCancellation()
            var result = AccessibilityReadResult(tree: root.map { [$0] } ?? [])
            result.text = readableText(result.tree)
            result.warnings = traversal.notes
            if result.tree.isEmpty {
                result.warnings.append("The app did not expose a readable accessibility tree for the selected window. Try capturing again after its content finishes loading.")
            }
            return result
        }
    }

    static func readableText(_ nodes: [AXNode]) -> String {
        var lines: [String] = []
        func append(_ value: String) {
            guard !value.isEmpty, lines.last != value else { return }
            lines.append(value)
        }
        func visit(_ node: AXNode) {
            guard !node.isProtected else { return }
            var seen = Set<String>()
            for text in [node.title, node.elementDescription, node.value, node.url] {
                if seen.insert(text).inserted { append(text) }
            }
            node.children.forEach(visit)
        }
        nodes.forEach(visit)
        return lines.joined(separator: "\n")
    }

    private static let protectedAttribute = NSAccessibility.Attribute.containsProtectedContent.rawValue

    /// Text areas can hold whole documents; every other attribute is a label.
    private static let documentRoles: Set<String> = [kAXTextAreaRole, kAXTextFieldRole]
    static let labelCharacterLimit = 8_192
    static let documentCharacterLimit = 120_000

    static func characterLimit(role: String, attribute: String) -> Int {
        attribute == kAXValueAttribute && documentRoles.contains(role) ? documentCharacterLimit : labelCharacterLimit
    }

    /// The states an app reports, in plain words. A checkbox or radio button's
    /// 0/1/2 value becomes its state instead of a bare number.
    static func states(role: String, value: Any?, enabled: Any?, focused: Any?,
                       selected: Any?, expanded: Any?) -> (states: [String], keepsValue: Bool) {
        var states: [String] = []
        var keepsValue = true
        if role == kAXCheckBoxRole || role == kAXRadioButtonRole, let number = value as? NSNumber {
            states.append(number.intValue == 1 ? "checked" : number.intValue == 2 ? "mixed" : "unchecked")
            keepsValue = false
        }
        if let expanded = expanded as? NSNumber { states.append(expanded.boolValue ? "expanded" : "collapsed") }
        if (selected as? NSNumber)?.boolValue == true { states.append("selected") }
        // A captured window is focused by definition; say so only of its contents.
        if role != kAXWindowRole, (focused as? NSNumber)?.boolValue == true { states.append("focused") }
        if (enabled as? NSNumber)?.boolValue == false { states.append("disabled") }
        return (states, keepsValue)
    }

    /// An element's global screen rectangle, or nil when the app does not report one.
    static func screenFrame(position: Any?, size: Any?) -> CGRect? {
        guard let position, let size else { return nil }
        let rawPosition = position as CFTypeRef
        let rawSize = size as CFTypeRef
        guard CFGetTypeID(rawPosition) == AXValueGetTypeID(), CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimension = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(rawPosition, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(rawSize, to: AXValue.self), .cgSize, &dimension),
              dimension.width > 0, dimension.height > 0 else { return nil }
        return CGRect(origin: point, size: dimension)
    }

    private static func copy(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value
    }

    private static func copyMany(_ element: AXUIElement, _ attributes: [String]) -> [Any]? {
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, attributes as CFArray, [], &values) == .success,
              let result = values as? [Any], result.count == attributes.count else { return nil }
        return result
    }

    private static func string(_ value: Any?) -> String {
        guard let value else { return "" }
        if let value = value as? String { return value }
        if let value = value as? URL { return value.absoluteString }
        if let value = value as? NSAttributedString { return value.string }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }

    private static func bool(_ value: Any?) -> Bool { (value as? NSNumber)?.boolValue ?? false }

    /// Unsupported/no-value means that the app does not implement this optional
    /// attribute. Any other IPC error means its security state is unknown.
    private static func unreadableSecurityAttribute(_ value: Any) -> Bool {
        let raw = value as CFTypeRef
        guard CFGetTypeID(raw) == AXValueGetTypeID() else { return false }
        let axValue = unsafeBitCast(raw, to: AXValue.self)
        guard AXValueGetType(axValue) == .axError else { return false }
        var error = AXError.success
        guard AXValueGetValue(axValue, .axError, &error) else { return true }
        return error != .success && error != .attributeUnsupported && error != .noValue
    }

    private final class Traversal {
        let started = ProcessInfo.processInfo.systemUptime
        var nodeCount = 0
        var characterCount = 0
        var notes: [String] = []
        var visited: [UInt: [AXUIElement]] = [:]

        var withinBudget: Bool {
            guard !Task.isCancelled else { note("Accessibility capture was cancelled; the tree is partial."); return false }
            guard ProcessInfo.processInfo.systemUptime - started < maximumSeconds else {
                note("Accessibility tree truncated after \(Int(maximumSeconds)) seconds to keep the app responsive.")
                return false
            }
            guard nodeCount < maximumNodes else {
                note("Accessibility tree truncated at \(maximumNodes) elements.")
                return false
            }
            guard characterCount < maximumCharacters else {
                note("Accessibility text truncated at \(maximumCharacters) characters.")
                return false
            }
            return true
        }

        func note(_ text: String) {
            if !notes.contains(text) { notes.append(text) }
        }

        func clipped(_ value: Any?, limit: Int = AccessibilityReader.labelCharacterLimit) -> String {
            let text = string(value).replacingOccurrences(of: "\0", with: "")
            let capacity = max(0, min(limit, maximumCharacters - characterCount))
            let output = String(text.prefix(capacity))
            characterCount += output.count
            if output.count < text.count { note("Some long accessibility attributes were truncated.") }
            return output
        }

        func visit(_ element: AXUIElement, depth: Int) -> AXNode? {
            guard withinBudget else { return nil }
            guard depth <= maximumDepth else {
                note("Accessibility tree truncated beyond \(maximumDepth) nesting levels.")
                return nil
            }
            let hash = CFHash(element)
            if visited[hash, default: []].contains(where: { CFEqual($0, element) }) { return nil }
            visited[hash, default: []].append(element)
            AXUIElementSetMessagingTimeout(element, perCallTimeout)

            // Never request text or children until secure/protected state is checked.
            guard let metadata = copyMany(element, [kAXRoleAttribute, kAXSubroleAttribute, protectedAttribute]) else {
                note("Some accessibility elements did not respond within the per-call timeout and were skipped.")
                return nil
            }
            let role = string(metadata[0])
            let subrole = string(metadata[1])
            guard !role.isEmpty else { return nil }
            guard !metadata.contains(where: unreadableSecurityAttribute) else {
                note("Some elements were skipped because their protected-content state could not be read.")
                return nil
            }
            let protected = subrole == kAXSecureTextFieldSubrole || role == kAXSecureTextFieldSubrole || bool(metadata[2])
            nodeCount += 1
            let id = nodeCount
            if protected {
                note("Protected accessibility elements were omitted. Screenshots retain the pixels shown by the app.")
                return AXNode(id: id, role: role, roleDescription: "protected field", isProtected: true)
            }

            guard withinTimeBudget else { return AXNode(id: id, role: role, roleDescription: role) }
            // One round trip reads the labels, location, and states together.
            let attributes = [kAXRoleDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute,
                              kAXDescriptionAttribute, kAXHelpAttribute, kAXURLAttribute, kAXPlaceholderValueAttribute,
                              kAXPositionAttribute, kAXSizeAttribute, kAXEnabledAttribute, kAXFocusedAttribute,
                              kAXSelectedAttribute, kAXExpandedAttribute]
            let values = copyMany(element, attributes)
            if values == nil { note("Some accessibility attributes could not be read; the tree is partial.") }
            let reported = states(role: role, value: values?[2], enabled: values?[9], focused: values?[10],
                                  selected: values?[11], expanded: values?[12])
            var node = AXNode(id: id, role: role, roleDescription: clipped(values?[0]),
                              title: clipped(values?[1]),
                              value: reported.keepsValue
                                ? clipped(values?[2], limit: characterLimit(role: role, attribute: kAXValueAttribute)) : "",
                              elementDescription: clipped(values?[3]), help: clipped(values?[4]),
                              url: clipped(values?[5]), placeholder: clipped(values?[6]))
            node.states = reported.states.isEmpty ? nil : reported.states
            node.screenFrame = screenFrame(position: values?[7], size: values?[8])
            if withinTimeBudget {
                var settable: DarwinBoolean = false
                if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success {
                    node.isSettable = settable.boolValue
                }
            }
            guard withinBudget else { return node }
            var count: CFIndex = 0
            let countStatus = AXUIElementGetAttributeValueCount(element, kAXChildrenAttribute as CFString, &count)
            guard countStatus == .success else {
                if countStatus != .attributeUnsupported && countStatus != .noValue {
                    note("Some accessibility child lists could not be read; the tree is partial.")
                }
                return node
            }
            guard count > 0, withinBudget else { return node }
            let limit = min(count, maximumNodes - nodeCount)
            if count > limit { note("Accessibility child lists were limited to fit the \(maximumNodes)-element budget.") }
            var children: CFArray?
            let childrenStatus = AXUIElementCopyAttributeValues(element, kAXChildrenAttribute as CFString, 0, limit, &children)
            guard childrenStatus == .success, let rawChildren = children as? [AXUIElement] else {
                if childrenStatus != .attributeUnsupported && childrenStatus != .noValue {
                    note("Some accessibility child lists could not be read; the tree is partial.")
                }
                return node
            }
            for child in rawChildren {
                guard withinBudget else { break }
                if let captured = visit(child, depth: depth + 1) { node.children.append(captured) }
            }
            return node
        }

        /// A node already allocated at the node cap can still receive its attributes.
        private var withinTimeBudget: Bool {
            guard ProcessInfo.processInfo.systemUptime - started < maximumSeconds, !Task.isCancelled else {
                note("Accessibility tree truncated after \(Int(maximumSeconds)) seconds to keep the app responsive.")
                return false
            }
            return true
        }
    }
}
