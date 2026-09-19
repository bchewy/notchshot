// SPDX-License-Identifier: MIT
import SwiftUI

struct ThemeSettingsView: View {
    @Bindable var store: CaptureStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Appearance")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(store.theme.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.65))
            }

            HStack(spacing: 4) {
                ForEach(NotchTheme.allCases) { theme in
                    themeButton(theme)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NotchStyle.subtle, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(NotchStyle.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func themeButton(_ theme: NotchTheme) -> some View {
        let isSelected = store.theme == theme

        return Button {
            store.theme = theme
        } label: {
            VStack(spacing: 5) {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 25, height: 25)
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.85))
                        }
                    }

                Text(theme.name)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(Color.white.opacity(isSelected ? 0.95 : 0.70))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? theme.accent.opacity(0.10) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? theme.accent.opacity(0.65) : Color.clear,
                                  lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.name) theme")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
