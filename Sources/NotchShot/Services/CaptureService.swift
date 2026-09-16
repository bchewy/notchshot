// SPDX-License-Identifier: MIT
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

struct CaptureWindowCandidate: Sendable {
    let id: UInt32
    let title: String
    let bounds: CGRect
    let layer: Int
}

enum CaptureServiceError: LocalizedError {
    case targetClosed
    case nothingCaptured(String)

    var errorDescription: String? {
        switch self {
        case .targetClosed: return "The selected app has closed. Switch to another app and capture again."
        case .nothingCaptured(let detail): return detail
        }
    }
}

/// Everything the store needs from the system to run a capture: which app is
/// in front, what the user has permitted, and the capture itself. Tests stand
/// in for ScreenCaptureKit, Accessibility, and the permission checks through it.
@MainActor
protocol CaptureServing: AnyObject {
    func frontmostTarget() -> CaptureTarget?
    func permissionStatus() -> PermissionStatus
    func capture(target: CaptureTarget, onScreenshot: ((CaptureResult) -> Void)?) async throws -> CaptureResult
}

@MainActor
final class CaptureService: CaptureServing {
    func frontmostTarget() -> CaptureTarget? {
        Self.target(for: NSWorkspace.shared.frontmostApplication)
    }

    func permissionStatus() -> PermissionStatus {
        PermissionService.status()
    }

    /// Only another regular app can be a target; NotchShot's own panels never are.
    static func target(for app: NSRunningApplication?) -> CaptureTarget? {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy == .regular else { return nil }
        return CaptureTarget(pid: app.processIdentifier, appName: app.localizedName ?? "Application",
                             bundleIdentifier: app.bundleIdentifier ?? "")
    }

    /// A single-window screenshot plus the selected window's AX tree. No screen
    /// stream, system-wide tree, menu traversal, background capture, or network.
    func capture(target: CaptureTarget, onScreenshot: ((CaptureResult) -> Void)? = nil) async throws -> CaptureResult {
        guard let app = NSRunningApplication(processIdentifier: target.pid), !app.isTerminated else {
            throw CaptureServiceError.targetClosed
        }
        let permissions = PermissionService.status()
        let capturedAt = Date()
        // Resolve these BEFORE the first await. Opening our preview or switching
        // apps during OCR cannot redirect this capture to a different window.
        let candidates = Self.windowCandidates(pid: target.pid)
        let focusedWindow = permissions.accessibility
            ? AccessibilityReader.snapshotFocusedWindow(pid: target.pid) : nil
        let selected = Self.selectWindow(candidates, focusedTitle: focusedWindow?.title,
                                         focusedBounds: focusedWindow?.bounds,
                                         hasFocusedWindow: focusedWindow != nil)
        var result = CaptureResult(date: capturedAt, appName: target.appName,
                                   bundleIdentifier: target.bundleIdentifier,
                                   windowTitle: focusedWindow?.title.isEmpty == false
                                    ? focusedWindow!.title : (selected?.title ?? "Untitled window"),
                                   windowID: selected?.id,
                                   sourceWindowFrame: selected?.bounds)

        if !permissions.accessibility {
            result.warnings.append("Accessibility access is off. Enable it in Settings to capture the app's text and element tree.")
        } else if focusedWindow == nil {
            result.warnings.append("The app did not expose its focused window through Accessibility. The screenshot uses its frontmost standard window, if available.")
        }
        if focusedWindow == nil, !permissions.accessibility {
            result.warnings.append("The screenshot uses the app's frontmost standard window because its focused accessibility window is unavailable.")
        }

        async let accessibility = readAccessibility(focusedWindow)
        var image: CGImage?
        if permissions.screenRecording {
            if let selected {
                do {
                    let screenshot = try await screenshot(windowID: selected.id, pid: target.pid)
                    image = screenshot.image
                    result.sourceWindowFrame = screenshot.windowFrame
                    if let image { result.pngData = Self.pngData(image) }
                    if result.pngData == nil { result.warnings.append("The screenshot could not be encoded as PNG. Accessibility content is still available.") }
                } catch {
                    result.warnings.append("Screenshot unavailable: \(error.localizedDescription) The window may have closed, moved to another Space, or declined capture. Try again, or check Screen Recording access.")
                }
            } else {
                result.warnings.append("The focused window could not be matched to a capturable window. Activate that window and capture again.")
            }
        } else {
            result.warnings.append("Screen Recording access is off. Enable it in Settings to include a screenshot, then relaunch NotchShot if macOS asks.")
        }

        if result.pngData != nil { onScreenshot?(result) }
        let axResult = await accessibility
        result.axTree = axResult.tree
        result.accessibilityText = axResult.text
        result.warnings += axResult.warnings
        if !result.axTree.isEmpty {
            result.warnings.append("Accessibility content is what this app exposes for the selected window and can include content outside the visible scroll area.")
        }
        // Chromium can expose toolbar controls before its document AX tree is
        // enabled. Do not mistake a large toolbar for captured page content.
        let browserWithoutDocument = Self.isChromiumBrowser(target.bundleIdentifier)
            && !Self.containsWebContent(result.axTree)
        if browserWithoutDocument, !result.axTree.isEmpty {
            result.warnings.append("This browser exposed controls but no web document tree. Its accessibility support may still be loading; try another capture. NotchShot does not change browser settings.")
        }
        // OCR is a local fallback only. It is never presented as accessibility text.
        if let image, result.accessibilityText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || result.elementCount < 5 || browserWithoutDocument {
            do {
                result.ocrText = try await OCRService.recognizeText(in: image)
                result.warnings.append("The accessibility tree was unavailable or limited; local OCR was run on the screenshot and is shown separately.")
            } catch {
                result.warnings.append("Local text recognition failed: \(error.localizedDescription)")
            }
        }
        guard result.pngData != nil || !result.axTree.isEmpty || !result.accessibilityText.isEmpty else {
            throw CaptureServiceError.nothingCaptured(result.warnings.joined(separator: "\n\n"))
        }
        return result
    }

    private func readAccessibility(_ snapshot: AccessibilityWindowSnapshot?) async -> AccessibilityReadResult {
        guard let snapshot else { return AccessibilityReadResult() }
        return await AccessibilityReader.read(window: snapshot)
    }

    private func screenshot(windowID: UInt32, pid: Int32) async throws -> (image: CGImage, windowFrame: CGRect) {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: {
            $0.windowID == windowID && $0.owningApplication?.processID == pid
        }) else {
            throw CaptureServiceError.nothingCaptured("The originally selected window is no longer available for capture.")
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        configuration.width = max(1, Int(ceil(filter.contentRect.width * scale)))
        configuration.height = max(1, Int(ceil(filter.contentRect.height * scale)))
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.captureResolution = .best
        configuration.shouldBeOpaque = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return (image, window.frame)
    }

    private static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func windowCandidates(pid: Int32) -> [CaptureWindowCandidate] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let records = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        // CGWindowList preserves front-to-back order; SCK's window array does not.
        return records.compactMap { record in
            guard (record[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  let number = record[kCGWindowNumber as String] as? NSNumber,
                  let dictionary = record[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                  bounds.width > 1, bounds.height > 1,
                  (record[kCGWindowAlpha as String] as? NSNumber)?.doubleValue != 0 else { return nil }
            return CaptureWindowCandidate(id: number.uint32Value,
                                          title: record[kCGWindowName as String] as? String ?? "",
                                          bounds: bounds,
                                          layer: (record[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0)
        }
    }

    /// Pure matching logic deliberately refuses to substitute an unrelated window
    /// when AX identified one but its geometry/title cannot be matched.
    nonisolated static func selectWindow(_ candidates: [CaptureWindowCandidate], focusedTitle: String?,
                                        focusedBounds: CGRect?, hasFocusedWindow: Bool) -> CaptureWindowCandidate? {
        guard hasFocusedWindow else { return candidates.first(where: { $0.layer == 0 }) }
        let title = focusedTitle ?? ""
        if let bounds = focusedBounds {
            let matchingBounds = candidates.filter { close($0.bounds, bounds) }
            if !title.isEmpty, let both = matchingBounds.first(where: { $0.title == title }) { return both }
            if let geometry = matchingBounds.first { return geometry }
        }
        if !title.isEmpty {
            let matchingTitle = candidates.filter { $0.title == title }
            // Identical titles on multiple windows cannot identify the focused one.
            if matchingTitle.count == 1 { return matchingTitle[0] }
        }
        return nil
    }

    private nonisolated static func close(_ first: CGRect, _ second: CGRect) -> Bool {
        abs(first.minX - second.minX) <= 3 && abs(first.minY - second.minY) <= 3 &&
        abs(first.width - second.width) <= 3 && abs(first.height - second.height) <= 3
    }

    private nonisolated static func isChromiumBrowser(_ bundleIdentifier: String) -> Bool {
        let identifier = bundleIdentifier.lowercased()
        return ["brave", "chrome", "chromium", "microsoft.edgemac", "company.thebrowser.browser", "vivaldi", "opera"]
            .contains(where: identifier.contains)
    }

    private nonisolated static func containsWebContent(_ nodes: [AXNode]) -> Bool {
        nodes.contains { $0.role == "AXWebArea" || containsWebContent($0.children) }
    }
}
