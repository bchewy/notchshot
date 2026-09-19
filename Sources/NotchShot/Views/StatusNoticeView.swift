// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// Brief feedback lives in the existing header slot. Opening its details keeps
/// a separate snapshot, so the expiry timer never dismisses something being read.
struct StatusNoticeView: View {
    @Environment(\.notchTheme) private var theme
    let notice: StatusNotice?
    let store: CaptureStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expiredNoticeID: UUID?
    @State private var inspectedNotice: StatusNotice?

    private var visibleNotice: StatusNotice? {
        // Keep the native popover's anchor and accessibility element alive
        // while its details are being read, even if newer feedback arrives.
        if let inspectedNotice { return inspectedNotice }
        guard let notice, notice.id != expiredNoticeID,
              !notice.isExpired(at: Date()) else { return nil }
        return notice
    }

    var body: some View {
        ZStack {
            if let current = visibleNotice {
                Button {
                    inspectedNotice = current
                } label: {
                    Label(current.title, systemImage: symbol(for: current))
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(noticeTint(for: current, theme: theme))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(noticeTint(for: current, theme: theme).opacity(0.1), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(current.title): \(current.message)")
                .accessibilityHint("Open notification details")
                .help("\(current.message) Click for details.")
                .id(current.id)
                .transition(.opacity)
            } else {
                Label("ON DEVICE", systemImage: "lock.fill")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(theme.accent.opacity(0.85))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.accent.opacity(0.08), in: Capsule())
                    .help("Captures stay on this Mac until you copy or export them.")
                    .transition(.opacity)
            }
        }
        .frame(width: 116, height: 22)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: visibleNotice?.id)
        .popover(item: $inspectedNotice, arrowEdge: .bottom) { selected in
            StatusNoticeDetailsView(notice: selected) {
                inspectedNotice = nil
            }
            .protectsNotchFromAutoCollapse(store)
        }
        .task(id: notice?.id) {
            guard let pending = notice else { return }
            let remaining = pending.remainingDuration(at: Date())
            if remaining > 0 {
                do { try await Task.sleep(for: .seconds(remaining)) }
                catch { return }
            }
            guard !Task.isCancelled, notice?.id == pending.id else { return }
            expiredNoticeID = pending.id
        }
    }
}

private struct StatusNoticeDetailsView: View {
    @Environment(\.notchTheme) private var theme
    let notice: StatusNotice
    let dismiss: () -> Void
    @State private var messageHeight: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(notice.title, systemImage: symbol(for: notice))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(noticeTint(for: notice, theme: theme))
                Spacer()
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(NotchIconButtonStyle())
                    .accessibilityLabel("Close notification details")
            }
            ScrollView {
                Text(notice.message)
                    .font(.system(size: 11))
                    .lineSpacing(3)
                    .lineLimit(nil)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { height in
                        messageHeight = height
                    }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(messageHeight, 20), 220))

            if let url = notice.revealURL {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .medium))
                .tint(theme.accent)
                .help("Reveal the exported capture folder in Finder.")
            }
        }
        .padding(14)
        .frame(width: 310)
        .preferredColorScheme(.dark)
    }
}

private func symbol(for notice: StatusNotice) -> String {
    switch notice.kind {
    case .success: "checkmark.circle.fill"
    case .info: "info.circle"
    case .error: "exclamationmark.circle.fill"
    }
}

private func noticeTint(for notice: StatusNotice, theme: NotchTheme) -> Color {
    notice.kind == .error ? .orange : theme.accent
}
