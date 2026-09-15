// SPDX-License-Identifier: MIT
import SwiftUI

/// Crisp native geometry for the tiny face, with the user's selected camera.
/// The drawing uses a 100 × 120 canvas and stays inside the existing strip lane.
struct PhotographerMascotView: View {
    let pose: PhotographerPose
    let camera: CaptureShutterSound
    var expansion: CGFloat = 0
    var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let ink = Color(red: 0.055, green: 0.20, blue: 0.16)
    private var progress: CGFloat { min(max(expansion, 0), 1) }
    private var width: CGFloat { 14 + 12 * progress }
    private var cameraLift: CGFloat { pose == .framing ? -22 : 0 }
    private var tilt: Double { pose == .shelving ? 5 : isHovered && pose == .idle ? -5 : 0 }

    var body: some View {
        ZStack {
            photographer
                .rotationEffect(.degrees(reduceMotion ? 0 : tilt), anchor: .bottom)
                .offset(y: !reduceMotion && isHovered && pose == .idle ? -2 : 0)
        }
        .frame(width: 100, height: 120)
        .scaleEffect(width / 100)
        .frame(width: width, height: width * 1.2)
        .clipped()
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.78), value: pose)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovered)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var photographer: some View {
        ZStack {
            MintPhotographerBody()
                .fill(LinearGradient(colors: [Color(red: 0.70, green: 0.98, blue: 0.85), NotchStyle.accent],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(MintPhotographerBody().stroke(Color.white.opacity(0.18), lineWidth: 1.2))

            Ellipse()
                .fill(Color.white.opacity(0.24))
                .frame(width: 24, height: 8)
                .rotationEffect(.degrees(-18))
                .position(x: 33, y: 24)

            HStack(spacing: 17) {
                eye
                eye
            }
            .position(x: 50, y: 42)

            Path { path in
                path.move(to: CGPoint(x: 44, y: 53))
                path.addQuadCurve(to: CGPoint(x: 56, y: 53), control: CGPoint(x: 50, y: 59))
            }
            .stroke(ink.opacity(0.8), style: StrokeStyle(lineWidth: 2.3, lineCap: .round))

            cameraBody
                .frame(width: 78, height: 49)
                .position(x: 50, y: 84 + cameraLift)

            // Paws stay above the camera edges as it rises toward the face.
            ForEach([16.0, 84.0], id: \.self) { x in
                Capsule()
                    .fill(NotchStyle.accent)
                    .overlay(Capsule().stroke(ink.opacity(0.18), lineWidth: 1))
                    .frame(width: 12, height: 19)
                    .rotationEffect(.degrees(x < 50 ? -14 : 14))
                    .position(x: x, y: 83 + cameraLift)
            }

            smallPrint
                .rotationEffect(.degrees(pose == .shelving ? 14 : -10))
                .scaleEffect(pose == .shelving ? 0.32 : 1)
                .opacity(pose == .holding ? 1 : 0)
                .position(x: pose == .shelving ? 76 : 73, y: pose == .shelving ? 112 : 85)
        }
    }

    private var eye: some View {
        Capsule()
            .fill(ink)
            .frame(width: 6.5, height: pose == .framing ? 5 : 9)
    }

    @ViewBuilder private var cameraBody: some View {
        if let image = CameraArtwork.images[camera] {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            // A missing optional artwork file must still leave a useful icon.
            Image(systemName: "camera.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(ink)
        }
    }

    private var smallPrint: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color(red: 0.96, green: 0.99, blue: 0.96))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(red: 0.19, green: 0.52, blue: 0.44))
                    .frame(width: 20, height: 16)
                    .padding(.top, 3)
            }
            .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(ink.opacity(0.25), lineWidth: 1))
            .frame(width: 26, height: 30)
    }
}

private struct MintPhotographerBody: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 14, y: 76))
        path.addCurve(to: CGPoint(x: 49, y: 12), control1: CGPoint(x: 9, y: 37), control2: CGPoint(x: 24, y: 11))
        path.addCurve(to: CGPoint(x: 87, y: 76), control1: CGPoint(x: 79, y: 10), control2: CGPoint(x: 92, y: 35))
        path.addCurve(to: CGPoint(x: 74, y: 112), control1: CGPoint(x: 94, y: 99), control2: CGPoint(x: 90, y: 113))
        path.addQuadCurve(to: CGPoint(x: 51, y: 108), control: CGPoint(x: 60, y: 114))
        path.addQuadCurve(to: CGPoint(x: 27, y: 113), control: CGPoint(x: 37, y: 115))
        path.addCurve(to: CGPoint(x: 14, y: 76), control1: CGPoint(x: 8, y: 112), control2: CGPoint(x: 7, y: 99))
        path.closeSubpath()
        return path.applying(CGAffineTransform(scaleX: rect.width / 100, y: rect.height / 120))
    }

}
