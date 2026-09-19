// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

@MainActor
struct ShotHoverPreviewView: View {
    static let size = CGSize(width: 320, height: 264)

    @Environment(\.notchTheme) private var theme
    let capture: CaptureResult
    let canCopy: Bool
    let copyLabel: String
    let clickLabel: String
    private let screenshot: NSImage?
    private let appIcon: NSImage?

    init(capture: CaptureResult, canCopy: Bool = false,
         copyLabel: String = "Copy shot", clickLabel: String = "Click shot to open") {
        self.capture = capture
        self.canCopy = canCopy
        self.copyLabel = copyLabel
        self.clickLabel = clickLabel
        screenshot = capture.pngData.flatMap(NSImage.init(data:))
        appIcon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: capture.bundleIdentifier)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Group {
                    if let appIcon {
                        Image(nsImage: appIcon).resizable().scaledToFit()
                    } else {
                        Image(systemName: "rectangle.on.rectangle")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(theme.accent)
                    }
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(capture.appName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(1)
                    Text(capture.windowTitle.isEmpty ? "Captured window" : capture.windowTitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 32)

            preview
                .frame(width: 296, height: 166)
                .background(Color.black.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(NotchStyle.border, lineWidth: 1))

            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(capture.date.formatted(date: .omitted, time: .shortened))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(contextSummary)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .font(.system(size: 9))
                .lineLimit(1)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    if canCopy { Text("⌘C  \(copyLabel)") }
                    Text(clickLabel)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(theme.accent.opacity(0.9))
            }
            .frame(height: 24)
        }
        .padding(12)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(white: 0.045), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .allowsHitTesting(false)
    }

    @ViewBuilder private var preview: some View {
        if let screenshot {
            Image(nsImage: screenshot).resizable().scaledToFit()
        } else {
            Text(excerpt)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.8))
                .lineSpacing(3)
                .lineLimit(9)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
        }
    }

    private var excerpt: String {
        let text = capture.readableText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return String(text.prefix(1_200)) }
        if !capture.axTree.isEmpty { return String(capture.treeText.prefix(1_200)) }
        return capture.warnings.first ?? "This shot has no screenshot or readable context. Click the shot to view its capture details."
    }

    private var contextSummary: String {
        var parts = [String]()
        if !capture.readableText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append("Text") }
        if capture.elementCount > 0 { parts.append("\(capture.elementCount) AX elements") }
        return parts.isEmpty ? (screenshot == nil ? "Context unavailable" : "Screenshot") : parts.joined(separator: " · ")
    }
}
