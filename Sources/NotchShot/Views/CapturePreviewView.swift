// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

struct CapturePreviewView: View {
    let capture: CaptureResult
    let tab: CaptureTab
    let accessibilityGranted: Bool
    let isCapturing: Bool
    let enableAccessibility: () -> Void
    let captureAgain: () -> Void
    @State private var treeSearch = ""

    var body: some View {
        VStack(spacing: 0) {
            switch tab {
            case .screenshot:
                screenshot
            case .text:
                textPreview
            case .tree:
                treePreview
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(NotchStyle.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onChange(of: capture.id) { _, _ in treeSearch = "" }
    }

    @ViewBuilder
    private var screenshot: some View {
        if let data = capture.pngData, let image = NSImage(data: data) {
            GeometryReader { geometry in
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: max(1, geometry.size.width - 16), height: max(1, geometry.size.height - 16))
                    .padding(8)
                    .accessibilityLabel("Screenshot of \(capture.appName), \(capture.windowTitle)")
            }
            Divider().overlay(NotchStyle.border)
            HStack(spacing: 5) {
                Image(systemName: "photo")
                if let representation = image.representations.first {
                    Text("\(representation.pixelsWide) × \(representation.pixelsHigh)")
                }
                Text("· PNG")
                Spacer()
                Text(capture.date, style: .time)
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.4))
            .padding(.horizontal, 11)
            .frame(height: 27)
        } else {
            PreviewUnavailableView(
                symbol: "photo.badge.exclamationmark",
                title: "No screenshot in this capture",
                detail: "Check Screen Recording in capture permissions, then capture again."
            )
        }
    }

    @ViewBuilder
    private var textPreview: some View {
        if capture.readableText.isEmpty {
            PreviewUnavailableView(
                symbol: "text.viewfinder",
                title: "No readable text found",
                detail: "Some apps expose little text. Try the screenshot or accessibility tree."
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !capture.accessibilityText.isEmpty {
                        textSection("ACCESSIBILITY TEXT", text: capture.accessibilityText)
                    }
                    if !capture.ocrText.isEmpty {
                        textSection("RECOGNIZED FROM IMAGE · OCR", text: capture.ocrText)
                    }
                    if !capture.importedText.isEmpty {
                        textSection("IMPORTED TEXT", text: capture.importedText)
                    }
                }
            }
            .defaultScrollAnchor(.top)
        }
    }

    private func textSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            previewHeading(title, detail: "\(text.count.formatted()) characters")
                .background(Color.white.opacity(0.025))
            Text(text)
                .font(.system(size: 12))
                .lineSpacing(4)
                .foregroundStyle(Color.white.opacity(0.83))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(14)
        }
    }

    @ViewBuilder
    private var treePreview: some View {
        if capture.axTree.isEmpty, capture.bundleIdentifier.isEmpty {
            PreviewUnavailableView(symbol: "square.and.arrow.down", title: "This drop did not include an accessibility tree", detail: "Images contain pixels, not app controls. Any text supplied with the drop is kept in the Text tab. Capture the original app with NotchShot to include its live tree.")
        } else if capture.axTree.isEmpty {
            unavailableAccessibility
        } else {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.white.opacity(0.35))
                TextField("Find in accessibility tree", text: $treeSearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !treeSearch.isEmpty {
                    Button { treeSearch = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear tree search")
                } else {
                    Text("\(capture.elementCount.formatted()) elements")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .fixedSize()
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
            Divider().overlay(NotchStyle.border)
            if filteredTree.isEmpty {
                PreviewUnavailableView(symbol: "magnifyingglass", title: "No matching elements", detail: "Try a role, title, value, or URL.")
            } else {
                ReadOnlyCaptureTextView(text: filteredTree)
                    .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            }
        }
    }

    private var unavailableAccessibility: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                Label(
                    accessibilityGranted ? "This capture has no accessibility tree" : "Accessibility is not enabled",
                    systemImage: accessibilityGranted ? "list.bullet.indent" : "lock"
                )
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))

                Text(accessibilityGranted
                     ? "Accessibility is enabled now. Open \(capture.appName) and capture again to read its tree. Saved captures do not update when permission changes."
                     : "Enable NotchShot in System Settings, then return to \(capture.appName) and capture again to include its text and controls.")
                    .font(.system(size: 11))
                    .lineSpacing(3)
                    .foregroundStyle(Color.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: accessibilityGranted ? captureAgain : enableAccessibility) {
                    Label(
                        accessibilityGranted ? "Capture again" : "Enable Accessibility",
                        systemImage: accessibilityGranted ? "camera.viewfinder" : "lock.open"
                    )
                }
                .buttonStyle(NotchActionStyle())
                .disabled(isCapturing)

                if accessibilityGranted {
                    Text("Some apps may still limit the accessibility information they share.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredTree: String {
        let query = treeSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return capture.treeText.replacingOccurrences(of: "\t", with: "  ") }
        return capture.treeText
            .components(separatedBy: .newlines)
            .filter { $0.localizedCaseInsensitiveContains(query) }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\t", with: "  ")
    }

    private func previewHeading(_ title: String, detail: String) -> some View {
        HStack {
            Text(title).tracking(0.7)
            Spacer()
            Text(detail)
        }
        .font(.system(size: 8, weight: .medium, design: .monospaced))
        .foregroundStyle(Color.white.opacity(0.4))
        .padding(.horizontal, 12)
        .frame(height: 30)
        .overlay(alignment: .bottom) { Rectangle().fill(NotchStyle.border).frame(height: 1) }
    }
}

struct PreviewUnavailableView: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.25))
                    .padding(.bottom, 2)
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 300)
            }
            .frame(maxWidth: .infinity)
            .padding(22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
