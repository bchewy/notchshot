// SPDX-License-Identifier: MIT
import SwiftUI

struct CaptureBehaviorSettingsView: View {
    @Environment(\.notchTheme) private var theme
    @Bindable var store: CaptureStore

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Capture & copy")
                .font(.system(size: 12, weight: .semibold))
            VStack(alignment: .leading, spacing: 5) {
                Text("Copy content").font(.system(size: 11))
                Picker("Copy content", selection: $store.copyContent) {
                    ForEach(CaptureCopyContent.allCases) { content in
                        Text(content.shortLabel).tag(content)
                            .accessibilityLabel(content.label)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                Text("\(store.copyContent.label) · Used for ⌘C, Copy shot, selected shots, and automatic copy.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Rectangle().fill(NotchStyle.border).frame(height: 1)
            settingToggle(
                "Copy after capture",
                detail: "Use your Copy content choice when a capture finishes.",
                isOn: $store.autoCopyCapture
            )
            Rectangle().fill(NotchStyle.border).frame(height: 1)
            settingToggle(
                "Paste image, then text",
                detail: store.copyContent == .screenshotAndTree
                    ? "After copying a shot, your next ⌘V pastes both in two steps. Wait a moment before typing. Uses Accessibility; ready for 2 minutes."
                    : "Available when Copy content is Screenshot + AX tree.",
                isOn: $store.pasteImageThenText
            )
            .disabled(store.copyContent != .screenshotAndTree)
            Rectangle().fill(NotchStyle.border).frame(height: 1)
            settingToggle(
                "Open shelf after capture",
                detail: "When off, captures won’t open the shelf automatically.",
                isOn: $store.openShelfAfterCapture
            )
            Rectangle().fill(NotchStyle.border).frame(height: 1)
            settingToggle(
                "Collapse after copying",
                detail: "Tuck away after ⌘C or a Copy button.",
                isOn: $store.collapseAfterCopy
            )
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NotchStyle.subtle, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(NotchStyle.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func settingToggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
        .tint(theme.accent)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }
}
