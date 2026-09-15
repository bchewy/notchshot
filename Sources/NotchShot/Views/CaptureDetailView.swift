// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// Inspect a shot only after it is selected from the shelf.
struct CaptureDetailView: View {
    @Bindable var store: CaptureStore
    let capture: CaptureResult
    @State private var tab: CaptureTab = .screenshot

    var body: some View {
        captureContent(capture)
            .onChange(of: capture.id, initial: true) { _, _ in
                if capture.pngData == nil, tab == .screenshot {
                    tab = capture.readableText.isEmpty ? .tree : .text
                }
            }
    }

    private func captureContent(_ capture: CaptureResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                captureIdentity(capture)
                Spacer(minLength: 4)
                if !capture.warnings.isEmpty {
                    CaptureNotesView(notes: capture.warnings, store: store, isExpanded: store.isExpanded)
                        .id(capture.id)
                }
                historyMenu
            }
            HStack(spacing: 3) {
                ForEach(CaptureTab.allCases) { item in
                    Button {
                        store.cancelCopyCollapse()
                        tab = item
                    } label: {
                        Label(item.rawValue, systemImage: item.symbol)
                            .font(.system(size: 11, weight: tab == item ? .semibold : .medium))
                            .foregroundStyle(tab == item ? .white : Color.white.opacity(0.45))
                            .frame(maxWidth: .infinity)
                            .frame(height: 25)
                            .background(tab == item ? Color.white.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(tab == item ? .isSelected : [])
                }
            }
            .padding(3)
            .background(NotchStyle.subtle, in: RoundedRectangle(cornerRadius: 10))

            CapturePreviewView(
                capture: capture,
                tab: tab,
                accessibilityGranted: store.accessibilityGranted,
                isCapturing: store.isCapturing,
                enableAccessibility: {
                    store.showingSettings = true
                    store.requestAccessibility()
                },
                captureAgain: store.captureFrontmost
            )
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)

            HStack(spacing: 6) {
                Button(action: copyCurrentTab) {
                    Label(tab.copyTitle, systemImage: "doc.on.doc")
                }
                .buttonStyle(NotchActionStyle(prominent: true))
                .disabled(!canCopy(capture))
                .opacity(canCopy(capture) ? 1 : 0.4)
                .help(tab == .tree ? "Copy the complete accessibility tree" : tab.copyTitle)
                Button(action: store.copyContext) {
                    Label("Copy all", systemImage: "square.on.square")
                }
                .buttonStyle(NotchActionStyle())
                .help("Copy the screenshot and app context to the clipboard")
                Spacer(minLength: 0)
                Button(action: store.exportSelected) {
                    Label("Export folder", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(NotchActionStyle())
            }
            .frame(height: 33)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: .infinity)
    }

    private func captureIdentity(_ capture: CaptureResult) -> some View {
        HStack(spacing: 8) {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: capture.bundleIdentifier) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                    .resizable().frame(width: 22, height: 22)
            } else {
                Image(systemName: "macwindow")
                    .font(.system(size: 17)).foregroundStyle(Color.white.opacity(0.5))
                    .frame(width: 22, height: 22)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(capture.appName).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Text(capture.windowTitle.isEmpty ? "Captured window" : capture.windowTitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(1)
                    .help(capture.windowTitle)
            }
        }
    }

    private var historyMenu: some View {
        Menu {
            ForEach(store.captures) { capture in
                Button {
                    store.showCaptureDetail(capture.id)
                } label: {
                    if capture.id == store.selectedID {
                        Label(historyTitle(capture), systemImage: "checkmark")
                    } else {
                        Text(historyTitle(capture))
                    }
                }
            }
            Divider()
            Button("Clear recent captures", role: .destructive, action: store.clearHistory)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                Text("Recent · \(store.captures.count)")
            }
            .font(.system(size: 10))
            .foregroundStyle(Color.white.opacity(0.5))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Recent captures are held in memory and cleared when you quit.")
    }

    private func historyTitle(_ capture: CaptureResult) -> String {
        "\(capture.appName) · \(capture.date.formatted(date: .omitted, time: .shortened))"
    }

    private func canCopy(_ capture: CaptureResult) -> Bool {
        switch tab {
        case .screenshot: capture.pngData != nil
        case .text: !capture.readableText.isEmpty
        case .tree: !capture.axTree.isEmpty
        }
    }

    private func copyCurrentTab() {
        switch tab {
        case .screenshot: store.copyImage()
        case .text: store.copyText()
        case .tree: store.copyTree()
        }
    }
}
