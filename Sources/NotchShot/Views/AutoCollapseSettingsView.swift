// SPDX-License-Identifier: MIT
import SwiftUI

struct AutoCollapseSettingsView: View {
    @Environment(\.notchTheme) private var theme
    @Bindable var store: CaptureStore

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle(isOn: $store.autoCollapseEnabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Collapse when away")
                        .font(.system(size: 11, weight: .medium))
                    Text("Tuck away when you leave. Returning resets the timer.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
            .tint(theme.accent)
            .accessibilityLabel("Collapse when away")
            .accessibilityHint("Automatically collapse after moving away. Stays open while you interact or a capture arrives.")

            HStack(spacing: 10) {
                Text("Wait")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Picker("Auto-collapse delay", selection: $store.autoCollapseDelay) {
                    ForEach([2, 3, 5, 10], id: \.self) { seconds in
                        Text("\(seconds)s").tag(Double(seconds))
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .disabled(!store.autoCollapseEnabled)
                .accessibilityValue("\(Int(store.autoCollapseDelay)) seconds")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NotchStyle.subtle, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(NotchStyle.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}
