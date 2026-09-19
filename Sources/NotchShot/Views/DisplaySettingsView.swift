// SPDX-License-Identifier: MIT
import SwiftUI

struct DisplaySettingsView: View {
    @Environment(\.notchTheme) private var theme
    @Bindable var store: CaptureStore

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Display")
                .font(.system(size: 12, weight: .semibold))

            Toggle(isOn: $store.followActiveScreen) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Follow active screen")
                        .font(.system(size: 11))
                    Text("Follow your pointer after a brief pause on another display. Off keeps the notch on the built-in or main display.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
            .tint(theme.accent)
            .accessibilityLabel("Follow active screen")
            .accessibilityHint("Follow the pointer’s display after a brief pause. Waits while capturing, dragging, or using the notch. Off returns to the built-in or main display.")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NotchStyle.subtle, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(NotchStyle.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}
