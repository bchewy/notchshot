#!/usr/bin/env swift
// SPDX-License-Identifier: MIT
// Draws the background of NotchShot's drag-to-Applications disk image and
// writes background.png and background@2x.png next to this script.
//
// Finder draws icon labels black in Light Mode and white in Dark Mode over any
// background, so the band behind the labels sits at about 18% luminance, where
// both read at roughly 4.5:1.
//
// Usage: swift script/dmg/make_background.swift
import AppKit
import CoreText
import Foundation
import UniformTypeIdentifiers

/// The window's content size in points; settings.py uses the same layout.
let size = CGSize(width: 640, height: 400)
let appCenter = CGPoint(x: 170, y: 180)
let applicationsCenter = CGPoint(x: 470, y: 180)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map(\.1) as CFArray,
               locations: stops.map(\.0))!
}

func drawText(_ context: CGContext, _ text: String, size: CGFloat, weight: NSFont.Weight,
              alpha: CGFloat, centerX: CGFloat, baseline: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(white: 1, alpha: alpha)
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
    context.saveGState()
    // The canvas is flipped; text needs its own upright matrix.
    context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    context.textPosition = CGPoint(x: centerX - width / 2, y: baseline)
    CTLineDraw(line, context)
    context.restoreGState()
}

func draw(_ context: CGContext, scale: CGFloat) {
    context.translateBy(x: 0, y: size.height * scale)
    context.scaleBy(x: scale, y: -scale)

    // Sage, lighter above and deeper below; about 18% luminance where labels sit.
    context.drawLinearGradient(gradient([(0, color(0.47, 0.56, 0.53)), (0.66, color(0.40, 0.49, 0.46)),
                                         (1, color(0.29, 0.37, 0.34))]),
                               start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
    // A soft mint light behind the two icons.
    for center in [appCenter, applicationsCenter] {
        context.drawRadialGradient(gradient([(0, color(0.70, 0.98, 0.85, 0.20)), (1, color(0.70, 0.98, 0.85, 0))]),
                                   startCenter: center, startRadius: 0, endCenter: center, endRadius: 150, options: [])
    }

    // The notch, hanging from the top of the window.
    let notch = CGMutablePath()
    let left = size.width / 2 - 78, right = size.width / 2 + 78, bottom: CGFloat = 28
    notch.move(to: CGPoint(x: left - 8, y: -1))
    notch.addArc(tangent1End: CGPoint(x: left, y: -1), tangent2End: CGPoint(x: left, y: 8), radius: 8)
    notch.addArc(tangent1End: CGPoint(x: left, y: bottom), tangent2End: CGPoint(x: left + 12, y: bottom), radius: 12)
    notch.addArc(tangent1End: CGPoint(x: right, y: bottom), tangent2End: CGPoint(x: right, y: bottom - 12), radius: 12)
    notch.addArc(tangent1End: CGPoint(x: right, y: -1), tangent2End: CGPoint(x: right + 8, y: -1), radius: 8)
    notch.closeSubpath()
    context.addPath(notch)
    context.setFillColor(color(0, 0, 0))
    context.fillPath()

    // The arrow from the app to Applications.
    let start = CGPoint(x: appCenter.x + 96, y: appCenter.y), end = CGPoint(x: applicationsCenter.x - 96, y: appCenter.y)
    context.setStrokeColor(color(1, 1, 1, 0.92))
    context.setLineWidth(5)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: start)
    context.addCurve(to: end, control1: CGPoint(x: start.x + 36, y: start.y - 22),
                     control2: CGPoint(x: end.x - 36, y: end.y - 22))
    context.strokePath()
    context.move(to: CGPoint(x: end.x - 15, y: end.y - 13))
    context.addLine(to: end)
    context.addLine(to: CGPoint(x: end.x - 18, y: end.y + 7))
    context.strokePath()

    drawText(context, "Drag NotchShot into Applications", size: 17, weight: .semibold, alpha: 0.96,
             centerX: size.width / 2, baseline: 326)
    drawText(context, "If macOS won’t open it, choose Open Anyway in System Settings → Privacy & Security.",
             size: 12, weight: .regular, alpha: 0.78, centerX: size.width / 2, baseline: 352)
}

func render(scale: CGFloat) -> CGImage {
    let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(context, scale: scale)
    return context.makeImage()!
}

func write(_ image: CGImage, dpi: CGFloat, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    // The DPI tells Finder that the @2x image covers the same 640 × 400 points.
    let properties = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary
    CGImageDestinationAddImage(destination, image, properties)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
try write(render(scale: 1), dpi: 72, to: directory.appendingPathComponent("background.png"))
try write(render(scale: 2), dpi: 144, to: directory.appendingPathComponent("background@2x.png"))
print("Wrote \(directory.appendingPathComponent("background.png").path) and background@2x.png")
