// SPDX-License-Identifier: MIT
import SwiftUI

struct HistorySettingsView: View {
    @Environment(\.notchTheme) private var theme
    @Bindable var history: ShotHistory
    @State private var confirmingClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("History")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if history.storageBytes > 0 {
                    Text(usage)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.65))
                }
            }

            Toggle(isOn: $history.isEnabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Keep shot history")
                        .font(.system(size: 11))
                    Text(history.isEnabled
                         ? "Saves each shot on this Mac so you can search and reopen it. Your shelf comes back after restarting."
                         : "Shots stay in memory and are gone when you quit. Saved shots never leave your Mac.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
            .tint(theme.accent)
            .accessibilityLabel("Keep shot history")
            .accessibilityHint("Saves each shot on this Mac so you can search and reopen it later.")

            if history.isEnabled {
                HStack(spacing: 10) {
                    Text("Keep")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Picker("Keep saved shots for", selection: $history.retention) {
                        ForEach(ShotHistory.Retention.allCases) { retention in
                            Text(retention.label).tag(retention)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .help("Unpinned shots older than this are deleted. Pinned shots stay until you delete them.")
                }
            }

            if history.storageBytes > 0 {
                clearRow
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NotchStyle.subtle, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(NotchStyle.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .onChange(of: history.isEnabled) { _, _ in confirmingClear = false }
    }

    @ViewBuilder private var clearRow: some View {
        HStack(spacing: 8) {
            if confirmingClear {
                Text("Delete every saved shot, including pinned ones?")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.orange.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                settingsButton("Cancel") { confirmingClear = false }
                settingsButton("Delete", destructive: true) {
                    history.deleteAll()
                    confirmingClear = false
                }
            } else {
                Text(history.isEnabled ? "Pinned shots are kept until you delete them." : "Shots saved earlier are still on this Mac.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                settingsButton(history.isEnabled ? "Clear history…" : "Delete saved shots…") { confirmingClear = true }
            }
        }
    }

    private var usage: String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(history.storageBytes), countStyle: .file)
        guard history.isEnabled else { return size }
        let count = history.entries.count
        return "\(count) \(count == 1 ? "shot" : "shots") · \(size)"
    }

    private func settingsButton(_ title: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 11, weight: .medium))
            .buttonStyle(.plain)
            .foregroundStyle(destructive ? Color.orange.opacity(0.9) : Color.white.opacity(0.7))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(NotchStyle.subtle, in: RoundedRectangle(cornerRadius: 7))
            .fixedSize()
    }
}
