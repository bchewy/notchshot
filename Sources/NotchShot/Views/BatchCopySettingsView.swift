// SPDX-License-Identifier: MIT
import SwiftUI

struct BatchCopySettingsView: View {
    @Bindable var store: CaptureStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Multi-shot context")
                .font(.system(size: 12, weight: .semibold))
            Picker("Context included when copying multiple shots", selection: $store.batchContextStyle) {
                ForEach(BatchContextStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            Text(store.batchContextStyle.help)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            Text("Review the copy from the shelf. Your original shots and exports stay unchanged.")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NotchStyle.subtle, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(NotchStyle.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}
