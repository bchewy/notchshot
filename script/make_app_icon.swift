#!/usr/bin/env swift
// SPDX-License-Identifier: MIT
// Draws NotchShot's app icon with Core Graphics and writes AppIcon.icns.
// Every size is drawn from the same vector geometry, so small sizes stay sharp.
//
// Usage: swift script/make_app_icon.swift [output.icns] [--preview directory]
import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: Palette (the app's Mint theme)

struct RGB {
    let r: CGFloat, g: CGFloat, b: CGFloat
    func color(_ alpha: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: alpha) }
    func mixed(with other: RGB, _ t: CGFloat) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }
}

let backgroundTop = RGB(r: 0.150, g: 0.200, b: 0.180)
let backgroundBottom = RGB(r: 0.040, g: 0.056, b: 0.050)
let mint = RGB(r: 0.54, g: 0.91, b: 0.77)
let mintHighlight = RGB(r: 0.78, g: 1.00, b: 0.89)
let mintDeep = RGB(r: 0.25, g: 0.66, b: 0.53)

// MARK: Geometry, in a 1024-point canvas with the origin at the top left

let canvas: CGFloat = 1024
let tile = CGRect(x: 100, y: 100, width: 824, height: 824) // Apple's app icon grid

/// Apple's app icon outline: a rounded rectangle whose corners ease into the
/// edges (continuous curvature). Radius 214 with 0.62 smoothing matches the
/// mask macOS 26 applies to app icons to within anti-aliasing.
func iconOutline(_ rect: CGRect, radius r: CGFloat = 214, smoothing s: CGFloat = 0.62) -> CGPath {
    // Corner smoothing as Figma describes it: a circular arc between two cubic
    // easings, each corner spanning (1 + s) × r along both of its edges.
    let span = (1 + s) * r
    let arcMeasure = CGFloat.pi / 2 * (1 - s)
    let arcSide = sin(arcMeasure / 2) * r * sqrt(2)
    let alpha = (CGFloat.pi / 2 - arcMeasure) / 2
    let beta = CGFloat.pi / 4 * s
    let c = r * tan(alpha / 2) * cos(beta), d = c * tan(beta)
    let b = (span - arcSide - c - d) / 3, a = 2 * b
    let path = CGMutablePath()
    // One corner, drawn with the corner at the origin: in along the top edge,
    // round, then down the right edge. Rotated into place for all four.
    let corners = [CGAffineTransform(translationX: rect.maxX, y: rect.minY),
                   CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: rect.maxX, ty: rect.maxY),
                   CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: rect.minX, ty: rect.maxY),
                   CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: rect.minX, ty: rect.minY)]
    for transform in corners {
        let start = CGPoint(x: -span, y: 0).applying(transform)
        path.isEmpty ? path.move(to: start) : path.addLine(to: start)
        path.addCurve(to: CGPoint(x: -span + a + b + c, y: d).applying(transform),
                      control1: CGPoint(x: -span + a, y: 0).applying(transform),
                      control2: CGPoint(x: -span + a + b, y: 0).applying(transform))
        path.addArc(center: CGPoint(x: -r, y: r), radius: r,
                    startAngle: -.pi / 2 + (.pi / 2 - arcMeasure) / 2, endAngle: -(.pi / 2 - arcMeasure) / 2,
                    clockwise: false, transform: transform)
        path.addCurve(to: CGPoint(x: 0, y: span).applying(transform),
                      control1: CGPoint(x: 0, y: span - a - b).applying(transform),
                      control2: CGPoint(x: 0, y: span - a).applying(transform))
    }
    path.closeSubpath()
    return path
}

/// The hardware notch hanging from the top edge, with its concave shoulders.
func notch(width: CGFloat, height: CGFloat, top: CGFloat) -> CGPath {
    let left = canvas / 2 - width / 2, right = canvas / 2 + width / 2, bottom = top + height
    let shoulder: CGFloat = 16, corner: CGFloat = 30
    let path = CGMutablePath()
    path.move(to: CGPoint(x: left - shoulder, y: top - 20))
    path.addLine(to: CGPoint(x: left - shoulder, y: top))
    path.addArc(tangent1End: CGPoint(x: left, y: top), tangent2End: CGPoint(x: left, y: top + shoulder), radius: shoulder)
    path.addArc(tangent1End: CGPoint(x: left, y: bottom), tangent2End: CGPoint(x: left + corner, y: bottom), radius: corner)
    path.addArc(tangent1End: CGPoint(x: right, y: bottom), tangent2End: CGPoint(x: right, y: bottom - corner), radius: corner)
    path.addArc(tangent1End: CGPoint(x: right, y: top), tangent2End: CGPoint(x: right + shoulder, y: top), radius: shoulder)
    path.addLine(to: CGPoint(x: right + shoulder, y: top - 20))
    path.closeSubpath()
    return path
}

/// The website's aperture: a circle with a hexagonal opening, each hexagon
/// edge extended to the rim to split the ring into six blades.
struct Aperture {
    let center: CGPoint
    let radius: CGFloat
    var opening: CGFloat { radius * 0.4747 }

    func angle(_ k: Int) -> CGFloat { (-90 + 60 * CGFloat(k)) * .pi / 180 }
    func vertex(_ k: Int) -> CGPoint {
        CGPoint(x: center.x + opening * cos(angle(k)), y: center.y + opening * sin(angle(k)))
    }
    /// Where the extension of the edge arriving at vertex k meets the rim.
    func rimPoint(_ k: Int) -> CGPoint {
        let start = vertex(k), direction = angle(k) + .pi / 3
        let dx = cos(direction), dy = sin(direction)
        let ox = start.x - center.x, oy = start.y - center.y
        let b = ox * dx + oy * dy, c = ox * ox + oy * oy - radius * radius
        let t = -b + sqrt(b * b - c)
        return CGPoint(x: start.x + t * dx, y: start.y + t * dy)
    }
    func blade(_ k: Int) -> CGPath {
        let path = CGMutablePath()
        let from = rimPoint(k), to = rimPoint(k + 1)
        path.move(to: vertex(k))
        path.addLine(to: from)
        path.addArc(center: center, radius: radius,
                    startAngle: atan2(from.y - center.y, from.x - center.x),
                    endAngle: atan2(to.y - center.y, to.x - center.x), clockwise: false)
        path.addLine(to: vertex(k + 1))
        path.closeSubpath()
        return path
    }
    var hexagon: CGPath {
        let path = CGMutablePath()
        path.addLines(between: (0..<6).map(vertex))
        path.closeSubpath()
        return path
    }
    /// Light falls from the upper left; each blade takes the tone of its facing.
    func tone(_ k: Int) -> RGB {
        let facing = angle(k) + .pi / 3 + .pi / 12
        let light = -3 * CGFloat.pi / 4
        let t = 0.2 + 0.6 * (1 + cos(facing - light)) / 2
        return t > 0.5 ? mint.mixed(with: mintHighlight, (t - 0.5) * 2) : mintDeep.mixed(with: mint, t * 2)
    }
}

// MARK: Drawing

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map(\.1) as CFArray,
               locations: stops.map(\.0))!
}

func drawIcon(_ context: CGContext, pixels: Int) {
    let scale = CGFloat(pixels) / canvas
    let small = pixels <= 32
    context.translateBy(x: 0, y: CGFloat(pixels))
    context.scaleBy(x: scale, y: -scale)
    let outline = iconOutline(tile)

    // A soft contact shadow, inside the grid's margin.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 28 * scale,
                      color: CGColor(gray: 0, alpha: 0.35))
    context.addPath(outline)
    context.setFillColor(backgroundBottom.color())
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(outline)
    context.clip()
    context.drawLinearGradient(gradient([(0, backgroundTop.color()), (1, backgroundBottom.color())]),
                               start: CGPoint(x: 0, y: tile.minY), end: CGPoint(x: 0, y: tile.maxY), options: [])

    let aperture = Aperture(center: CGPoint(x: canvas / 2, y: small ? 548 : 556), radius: small ? 300 : 262)
    context.drawRadialGradient(gradient([(0, mint.color(0.34)), (0.45, mint.color(0.12)), (1, mint.color(0))]),
                               startCenter: aperture.center, startRadius: 0,
                               endCenter: aperture.center, endRadius: aperture.radius * 1.55, options: [])

    // The lens behind the opening.
    context.saveGState()
    context.addPath(aperture.hexagon)
    context.clip()
    context.drawRadialGradient(gradient([(0, CGColor(srgbRed: 0.06, green: 0.13, blue: 0.10, alpha: 1)),
                                         (1, CGColor(srgbRed: 0.01, green: 0.02, blue: 0.02, alpha: 1))]),
                               startCenter: aperture.center, startRadius: 0,
                               endCenter: aperture.center, endRadius: aperture.opening, options: [])
    if !small {
        let glint = CGPoint(x: aperture.center.x - aperture.opening * 0.3, y: aperture.center.y - aperture.opening * 0.32)
        context.drawRadialGradient(gradient([(0, mintHighlight.color(0.55)), (0.35, mintHighlight.color(0.18)), (1, mintHighlight.color(0))]),
                                   startCenter: glint, startRadius: 0,
                                   endCenter: glint, endRadius: aperture.opening * 0.55, options: [])
    }
    context.restoreGState()

    // The blades, lifted off the background.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12 * scale), blur: 34 * scale,
                      color: CGColor(gray: 0, alpha: 0.5))
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    for k in 0..<6 {
        context.addPath(aperture.blade(k))
        context.setFillColor(aperture.tone(k).color())
        context.fillPath()
    }
    context.setBlendMode(.sourceAtop)
    let top = aperture.center.y - aperture.radius, bottom = aperture.center.y + aperture.radius
    context.drawLinearGradient(gradient([(0, CGColor(gray: 1, alpha: 0.22)), (0.5, CGColor(gray: 1, alpha: 0)),
                                         (1, CGColor(gray: 0, alpha: 0.14))]),
                               start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom), options: [])
    // Cut the gaps between blades, never thinner than about a pixel.
    let gap = max(aperture.radius * 0.042, 0.9 / scale)
    if pixels >= 32 {
        context.setBlendMode(.clear)
        context.setLineWidth(gap)
        context.setLineCap(.butt)
        for k in 0..<6 {
            let start = aperture.vertex(k), end = aperture.rimPoint(k)
            let dx = end.x - start.x, dy = end.y - start.y
            context.move(to: start)
            context.addLine(to: CGPoint(x: end.x + dx * 0.1, y: end.y + dy * 0.1))
        }
        context.strokePath()
    }
    context.endTransparencyLayer()
    context.restoreGState()

    // A faint light along the top edge.
    context.saveGState()
    context.addPath(outline)
    context.setLineWidth(4)
    context.replacePathWithStrokedPath()
    context.clip()
    context.drawLinearGradient(gradient([(0, CGColor(gray: 1, alpha: 0.18)), (0.35, CGColor(gray: 1, alpha: 0))]),
                               start: CGPoint(x: 0, y: tile.minY), end: CGPoint(x: 0, y: tile.maxY), options: [])
    context.restoreGState()

    // The notch, with its camera.
    context.addPath(notch(width: small ? 360 : 300, height: small ? 84 : 70, top: tile.minY))
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fillPath()
    if !small {
        let camera = CGPoint(x: canvas / 2, y: tile.minY + 33)
        context.setFillColor(CGColor(srgbRed: 0.05, green: 0.09, blue: 0.11, alpha: 1))
        context.fillEllipse(in: CGRect(x: camera.x - 11, y: camera.y - 11, width: 22, height: 22))
        context.setFillColor(CGColor(srgbRed: 0.12, green: 0.24, blue: 0.30, alpha: 1))
        context.fillEllipse(in: CGRect(x: camera.x - 6, y: camera.y - 6, width: 12, height: 12))
        context.setFillColor(CGColor(gray: 1, alpha: 0.45))
        context.fillEllipse(in: CGRect(x: camera.x - 4.5, y: camera.y - 4.5, width: 4, height: 4))
    }
    context.restoreGState()
}

func render(pixels: Int) -> CGImage {
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    drawIcon(context, pixels: pixels)
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

// MARK: Output

var arguments = Array(CommandLine.arguments.dropFirst())
var previewDirectory: URL?
if let flag = arguments.firstIndex(of: "--preview"), flag + 1 < arguments.count {
    previewDirectory = URL(fileURLWithPath: arguments[flag + 1])
    arguments.removeSubrange(flag...flag + 1)
}
let output = URL(fileURLWithPath: arguments.first ?? "Sources/NotchShot/Resources/AppIcon.icns")
let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("NotchShot-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

for points in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = factor == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try writePNG(render(pixels: points * factor), to: iconset.appendingPathComponent(name))
    }
}
if let previewDirectory {
    try FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
    for pixels in [1024, 256, 64, 32, 16] {
        try writePNG(render(pixels: pixels), to: previewDirectory.appendingPathComponent("AppIcon-\(pixels).png"))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", "--output", output.path, iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed.\n".utf8))
    exit(1)
}
print("Wrote \(output.path)")
