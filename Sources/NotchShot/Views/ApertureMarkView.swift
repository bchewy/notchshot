// SPDX-License-Identifier: MIT
import SwiftUI

/// The notch's left-lane mark: a six-blade aperture in the theme color. It
/// closes like a shutter while capturing and reopens as the shot lands.
struct ApertureMarkView: View {
    @Environment(\.notchTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: ApertureState
    var expansion: CGFloat = 0
    var isHovered = false

    private var size: CGFloat { 13 + 9 * min(max(expansion, 0), 1) }
    private var turn: Double { state.turn + (isHovered && state == .open ? 22 : 0) }

    var body: some View {
        ZStack {
            ApertureShape(part: .blades, opening: state.opening, turn: turn)
                .fill(LinearGradient(colors: [theme.apertureHighlight, theme.accent],
                                     startPoint: .topLeading, endPoint: .bottomTrailing),
                      style: FillStyle(eoFill: true))
            ApertureShape(part: .seams, opening: state.opening, turn: turn)
                .stroke(Color.black.opacity(0.6), style: StrokeStyle(lineWidth: max(0.75, size * 0.055), lineCap: .round))
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.7), value: state)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isHovered)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Six blades around a hexagonal opening. Each seam continues one side of the
/// opening out to the rim, so closing the opening turns the pinwheel.
struct ApertureShape: Shape {
    enum Part { case blades, seams }

    let part: Part
    var opening: CGFloat
    var turn: Double

    var animatableData: AnimatablePair<CGFloat, Double> {
        get { AnimatablePair(opening, turn) }
        set { opening = newValue.first; turn = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let rim = min(rect.width, rect.height) / 2
        let hole = rim * (0.1 + 0.52 * min(max(opening, 0), 1))
        let start = (turn - 90) * .pi / 180
        let vertices = (0..<6).map { index -> CGPoint in
            let angle = start + Double(index) * .pi / 3
            return CGPoint(x: center.x + hole * cos(angle), y: center.y + hole * sin(angle))
        }
        var path = Path()
        switch part {
        case .blades:
            path.addEllipse(in: CGRect(x: center.x - rim, y: center.y - rim, width: rim * 2, height: rim * 2))
            path.addLines(vertices)
            path.closeSubpath()
        case .seams:
            for index in 0..<6 {
                let from = vertices[index], to = vertices[(index + 1) % 6]
                let length = hypot(to.x - from.x, to.y - from.y)
                guard length > 0 else { continue }
                let direction = CGPoint(x: (to.x - from.x) / length, y: (to.y - from.y) / length)
                // Where the side's continuation meets the rim.
                let offset = CGPoint(x: to.x - center.x, y: to.y - center.y)
                let along = offset.x * direction.x + offset.y * direction.y
                let reach = -along + sqrt(max(0, along * along - (offset.x * offset.x + offset.y * offset.y - rim * rim)))
                path.move(to: to)
                path.addLine(to: CGPoint(x: to.x + direction.x * reach, y: to.y + direction.y * reach))
            }
        }
        return path
    }
}
