// SPDX-License-Identifier: MIT
import SwiftUI

/// Saved shots, newest first. Opening one puts it back on the shelf.
struct HistoryView: View {
    @Environment(\.notchTheme) private var theme
    @Bindable var store: CaptureStore
    @Bindable var history: ShotHistory
    @State private var scrollbarProtection = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                searchField
                Toggle(isOn: $history.showsPinnedOnly) {
                    Label("Pinned", systemImage: history.showsPinnedOnly ? "pin.fill" : "pin")
                        .font(.system(size: 10, weight: .medium))
                }
                .toggleStyle(.button)
                .buttonStyle(.plain)
                .foregroundStyle(history.showsPinnedOnly ? theme.accent : Color.white.opacity(0.55))
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(history.showsPinnedOnly ? theme.accent.opacity(0.12) : NotchStyle.subtle, in: RoundedRectangle(cornerRadius: 8))
                .help("Show only pinned shots")
                .accessibilityLabel("Show only pinned shots")
            }

            let results = history.results
            if history.entries.isEmpty {
                PreviewUnavailableView(symbol: "clock.arrow.circlepath", title: "No saved shots yet",
                                       detail: "New shots are saved here as you capture them.")
            } else if results.isEmpty {
                PreviewUnavailableView(symbol: "magnifyingglass", title: history.showsPinnedOnly && history.query.isEmpty
                                       ? "No pinned shots" : "No matching shots",
                                       detail: history.showsPinnedOnly && history.query.isEmpty
                                       ? "Pin a shot to keep it past your history limit."
                                       : "Search looks at app names, window titles, and captured text.")
            } else {
                NotchScrollView(
                    accessibilityLabel: "History scroll position",
                    onDraggingChange: { store.setAutoCollapseProtection(owner: scrollbarProtection, active: $0) }
                ) {
                    LazyVStack(spacing: 4) {
                        ForEach(results) { entry in
                            HistoryRow(entry: entry, store: store, history: history)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.white.opacity(0.35))
            TextField("Search shots", text: $history.query)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            if !history.query.isEmpty {
                Button { history.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(NotchStyle.subtle, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(NotchStyle.border, lineWidth: 1))
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let failure = history.failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.orange.opacity(0.8))
            } else {
                Text(summary)
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 10))
        .lineLimit(1)
        .frame(height: 14)
    }

    private var summary: String {
        let count = history.entries.count
        let size = ByteCountFormatter.string(fromByteCount: Int64(history.storageBytes), countStyle: .file)
        let kept = history.retention == .forever ? "kept forever" : "kept for \(history.retention.label) unless pinned"
        return "\(count) \(count == 1 ? "shot" : "shots") · \(size) · \(kept)"
    }
}

private struct HistoryRow: View {
    @Environment(\.notchTheme) private var theme
    let entry: ShotHistoryEntry
    let store: CaptureStore
    let history: ShotHistory
    @State private var thumbnail: NSImage?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 9) {
            Button { store.openFromHistory(entry.id) } label: {
                HStack(spacing: 9) {
                    preview
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.windowTitle.isEmpty ? entry.appName : entry.windowTitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.88))
                            .lineLimit(1)
                        Text(detail)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.42))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open on the shelf")
            .accessibilityLabel("Open \(entry.appName) shot, \(entry.windowTitle)")
            .accessibilityValue(detail)

            rowButton(entry.isPinned ? "pin.fill" : "pin", active: entry.isPinned,
                      label: entry.isPinned ? "Unpin shot" : "Pin shot",
                      help: entry.isPinned ? "Unpin; it will follow your history limit" : "Pin to keep this shot past your history limit") {
                history.setPinned(!entry.isPinned, for: entry.id)
            }
            rowButton("doc.on.doc", label: "Copy shot", help: "Copy with your Copy content setting") {
                store.copyFromHistory(entry.id)
            }
            rowButton("trash", label: "Delete from history", help: "Delete from history. The shelf is not changed.") {
                history.delete([entry.id])
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(isHovered ? Color.white.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
        .onHover { isHovered = $0 }
        .task(id: entry.id) { thumbnail = await history.thumbnail(for: entry.id) }
        .accessibilityElement(children: .contain)
    }

    private var detail: String {
        var parts = [entry.appName, entry.capturedAt.formatted(.relative(presentation: .named))]
        if entry.elementCount > 0 { parts.append("\(entry.elementCount.formatted()) elements") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var preview: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFill()
            } else {
                Image(systemName: entry.hasScreenshot ? "photo" : "text.alignleft")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
        }
        .frame(width: 56, height: 36)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(NotchStyle.border, lineWidth: 1))
    }

    private func rowButton(_ symbol: String, active: Bool = false, label: String, help: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(active ? theme.accent : Color.white.opacity(isHovered ? 0.6 : 0.3))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(label)
    }
}
