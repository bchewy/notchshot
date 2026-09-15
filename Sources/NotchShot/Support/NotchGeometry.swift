// SPDX-License-Identifier: GPL-3.0-only
// Adapted from sk-ruban/notchi NSScreen+Notch.swift, e873da231340b3a5094c59ce7cb0ec2809d88ed1.
// Uses public screen geometry only; see THIRD_PARTY_NOTICES.md.
import AppKit

enum NotchGeometry {
    static var preferredScreen: NSScreen? {
        NSScreen.screens.first {
            guard let id = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
            return CGDisplayIsBuiltin(id) != 0
        } ?? NSScreen.main ?? NSScreen.screens.first
    }

    static func dimensions(for screen: NSScreen) -> CGSize {
        notchRect(for: screen).size
    }

    static func frame(on screen: NSScreen, size: CGSize) -> CGRect {
        frame(anchoredTo: notchRect(for: screen), size: size)
    }

    private static func notchRect(for screen: NSScreen) -> CGRect {
        notchRect(
            in: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            leftAreaWidth: screen.auxiliaryTopLeftArea?.width,
            rightAreaWidth: screen.auxiliaryTopRightArea?.width
        )
    }

    /// The safe areas can differ by a pixel. Derive the cutout's center from
    /// their widths, relative to this display's origin, rather than assuming
    /// that it lies exactly at the display's midpoint.
    static func notchRect(in screenFrame: CGRect, safeAreaTop: CGFloat, leftAreaWidth: CGFloat?, rightAreaWidth: CGFloat?) -> CGRect {
        var centerX = screenFrame.midX
        var width: CGFloat = 190
        let height = safeAreaTop > 0 ? max(28, safeAreaTop) : 28
        if safeAreaTop > 0, let left = leftAreaWidth, let right = rightAreaWidth,
           left >= 0, right >= 0, left + right < screenFrame.width {
            let gapWidth = screenFrame.width - left - right
            centerX = screenFrame.minX + left + gapWidth / 2
            width = max(140, gapWidth + 4)
        }
        return CGRect(x: centerX - width / 2, y: screenFrame.maxY - height, width: width, height: height)
    }

    static func frame(anchoredTo notch: CGRect, size: CGSize) -> CGRect {
        CGRect(x: notch.midX - size.width / 2, y: notch.maxY - size.height, width: size.width, height: size.height)
    }
}
