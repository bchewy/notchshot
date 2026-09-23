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

            laneHeading("Left of the notch")
            HStack(spacing: 4) {
                ForEach(NotchMark.allCases) { mark in
                    laneButton(mark.name, isSelected: store.notchMark == mark,
                               accessibilityLabel: "\(mark.name) mark left of the notch") {
                        store.notchMark = mark
                    } preview: {
                        if mark == .none {
                            noneGlyph
                        } else {
                            NotchMarkView(mark: mark, state: .open, expansion: 1)
                        }
                    }
                }
            }

            laneHeading("Right of the notch")
            HStack(spacing: 4) {
                ForEach(NotchIndicator.allCases) { indicator in
                    laneButton(indicator.name, isSelected: store.notchIndicator == indicator,
                               accessibilityLabel: "\(indicator.name) right of the notch") {
                        store.notchIndicator = indicator
                    } preview: {
                        switch indicator {
                        case .shotCount:
                            Text("3")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(store.theme.accent)
                        case .statusDot:
                            Circle().fill(store.theme.accent).frame(width: 6, height: 6)
                        case .none:
                            noneGlyph
                        }
                    }
                }
            }
            Text("Capturing and missing permissions always show on the right.")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NotchStyle.subtle, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(NotchStyle.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func laneHeading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.55))
            .padding(.top, 2)
    }

    private var noneGlyph: some View {
        Capsule()
            .fill(Color.white.opacity(0.25))
            .frame(width: 10, height: 2)
    }

    private func laneButton<Preview: View>(_ name: String, isSelected: Bool, accessibilityLabel: String,
                                           action: @escaping () -> Void,
                                           @ViewBuilder preview: () -> Preview) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                preview()
                    .frame(width: 25, height: 25)
                Text(name)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(Color.white.opacity(isSelected ? 0.95 : 0.70))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? store.theme.accent.opacity(0.10) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? store.theme.accent.opacity(0.65) : Color.clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
