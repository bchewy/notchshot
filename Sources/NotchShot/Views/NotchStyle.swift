// SPDX-License-Identifier: MIT
import SwiftUI

enum NotchStyle {
    static let accent = Color(red: 0.54, green: 0.91, blue: 0.77)
    static let subtle = Color.white.opacity(0.055)
    static let border = Color.white.opacity(0.09)
    static let expandedWidth: CGFloat = 440
    static let expandedHeight: CGFloat = 480
    static let collapsedWingWidth: CGFloat = 16

    static func collapsedSize(notchSize: CGSize) -> CGSize {
        // Two small indicator lanes and 2 pt outer padding per side. Keep
        // actual window bounds tight so menu items beside it remain usable.
        CGSize(width: notchSize.width + collapsedWingWidth * 2 + 4,
               height: max(notchSize.height, 32))
    }

    static func expandedSize(for page: NotchPage) -> CGSize {
        let height: CGFloat
        switch page {
        case .shelf: height = 180
        case .settings: height = 440
        case .detail: height = expandedHeight
        }
        return CGSize(width: expandedWidth, height: height)
    }
}

struct NotchSurface: Shape {
    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(
            topLeadingRadius: 9,
            bottomLeadingRadius: 25,
            bottomTrailingRadius: 25,
            topTrailingRadius: 9
        ).path(in: rect)
    }
}

struct NotchActionStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(prominent ? Color.black : Color.white.opacity(0.88))
            .padding(.horizontal, 9)
            .frame(height: 33)
            .background(prominent ? NotchStyle.accent : NotchStyle.subtle, in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                if !prominent {
                    RoundedRectangle(cornerRadius: 9).strokeBorder(NotchStyle.border, lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.65 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 9))
    }
}

struct NotchIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.white.opacity(configuration.isPressed ? 1 : 0.5))
            .frame(width: 26, height: 26)
            .background(NotchStyle.subtle, in: Circle())
            .contentShape(Circle())
    }
}

enum CaptureTab: String, CaseIterable, Identifiable {
    case screenshot = "Screenshot"
    case text = "Text"
    case tree = "AX tree"

    var id: Self { self }
    var symbol: String {
        switch self {
        case .screenshot: "photo"
        case .text: "text.alignleft"
        case .tree: "list.bullet.indent"
        }
    }
    var copyTitle: String {
        switch self {
        case .screenshot: "Copy image"
        case .text: "Copy text"
        case .tree: "Copy tree"
        }
    }
}
