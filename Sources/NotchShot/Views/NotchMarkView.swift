// SPDX-License-Identifier: MIT
import SwiftUI

/// The left-lane mark chosen in Appearance. Every mark follows the same
/// capture progress and fits the 16-point collapsed lane.
struct NotchMarkView: View {
    let mark: NotchMark
    let state: ShutterState
    var expansion: CGFloat = 0
    var isHovered = false

    var body: some View {
        switch mark {
        case .aperture:
            ApertureMarkView(state: state, expansion: expansion, isHovered: isHovered)
        case .viewfinder:
            ViewfinderMarkView(state: state, expansion: expansion, isHovered: isHovered)
        case .camera:
            CameraMarkView(state: state, expansion: expansion, isHovered: isHovered)
        case .none:
            Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
        }
    }

    static func size(for expansion: CGFloat) -> CGFloat {
        13 + 9 * min(max(expansion, 0), 1)
    }
}

/// Corner brackets that snap in around a flash while capturing.
struct ViewfinderMarkView: View {
    @Environment(\.notchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: ShutterState
    var expansion: CGFloat = 0
    var isHovered = false

    private var size: CGFloat { NotchMarkView.size(for: expansion) }
    private var inset: CGFloat {
        switch state {
        case .open: isHovered ? -0.05 : 0
        case .shut: 0.16
        case .half: 0.08
        case .reopening: -0.08
        }
    }

    var body: some View {
        ZStack {
            ViewfinderShape(inset: inset)
                .stroke(LinearGradient(colors: [theme.apertureHighlight, theme.accent],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: max(1.3, size * 0.12), lineCap: .round, lineJoin: .round))
            Circle()
                .fill(theme.accent)
                .frame(width: size * 0.24, height: size * 0.24)
                .scaleEffect(state == .shut ? 1 : 0.4)
                .opacity(state == .shut || state == .half ? 1 : 0)
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.68), value: state)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isHovered)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ViewfinderShape: Shape {
    /// A fraction of the size; positive moves the brackets toward the center.
    var inset: CGFloat

    var animatableData: CGFloat {
        get { inset }
        set { inset = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let frame = rect.insetBy(dx: rect.width * (0.1 + inset), dy: rect.height * (0.1 + inset))
        // Arms scale with the frame, so closing in never joins them into a box.
        let arm = frame.width * 0.3
        var path = Path()
        for (corner, dx, dy) in [(CGPoint(x: frame.minX, y: frame.minY), 1.0, 1.0),
                                 (CGPoint(x: frame.maxX, y: frame.minY), -1.0, 1.0),
                                 (CGPoint(x: frame.minX, y: frame.maxY), 1.0, -1.0),
                                 (CGPoint(x: frame.maxX, y: frame.maxY), -1.0, -1.0)] {
            path.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
        }
        return path
    }
}

/// A camera that presses in with a flash, then shows a print peeking out.
struct CameraMarkView: View {
    @Environment(\.notchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: ShutterState
    var expansion: CGFloat = 0
    var isHovered = false

    private var size: CGFloat { NotchMarkView.size(for: expansion) }
    private var showsPrint: Bool { state == .half || state == .reopening }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.06)
                .fill(Color.white.opacity(0.92))
                .frame(width: size * 0.5, height: size * 0.42)
                .offset(y: showsPrint ? size * (state == .reopening ? 0.7 : 0.52) : size * 0.1)
                .opacity(state == .half ? 1 : 0)
            Image(systemName: "camera.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(LinearGradient(colors: [theme.apertureHighlight, theme.accent],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size * 0.8)
                .scaleEffect(state == .shut ? 0.86 : 1)
                .rotationEffect(.degrees(isHovered && state == .open ? -8 : 0))
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(Color.white)
                .offset(x: size * 0.46, y: -size * 0.42)
                .scaleEffect(state == .shut ? 1 : 0.2)
                .opacity(state == .shut ? 1 : 0)
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.7), value: state)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isHovered)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
