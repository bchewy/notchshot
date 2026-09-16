// SPDX-License-Identifier: MIT
import AppKit
import ImageIO

/// Offers the screenshot and its context as one rich document, with independent
/// image and plain-text alternatives for destinations that do not accept rich text.
@MainActor
enum CaptureClipboardService {
    static let batchIdentifierType = NSPasteboard.PasteboardType("com.bchewy.notchshot.batch-identity")

    /// A single rich document keeps all selected images in shelf order. Publishing
    /// just its first PNG as an alternative would silently discard the other shots
    /// in image-preferring destinations, so that fallback is only offered for one image.
    static func makeItem(for batch: CaptureBatch) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        let images = validatedImages(for: batch)
        if !images.isEmpty, let rtfd = richDocument(images: images, context: batch.contextText) {
            item.setData(rtfd, forType: .rtfd)
        }
        item.setString(htmlDocument(images: images, context: batch.contextText), forType: .html)
        if images.count == 1, let image = images.first {
            item.setData(image.png, forType: .png)
            // PNG is sufficient for image receivers. Avoid eagerly decoding a
            // potentially 40-megapixel original just to offer a TIFF alternative.
        }
        item.setString(batch.contextText, forType: .string)
        item.setString(batch.identity, forType: batchIdentifierType)
        return item
    }

    /// Shared by rich copy and assisted paste so both use exactly the same ordered,
    /// decodable images. Small previews validate image data without retaining full decodes.
    nonisolated static func validImagePNGs(for batch: CaptureBatch) -> [Data] {
        batch.captures.compactMap { capture in
            guard !batch.unavailableImageIDs.contains(capture.id),
                  let png = capture.pngData, validatedPreview(png: png) != nil else { return nil }
            return png
        }
    }

    /// Safe to prepare alongside batch text on a background task. This uses the
    /// same decoder boundary as rich copy and never constructs AppKit objects.
    /// Missing screenshots are already represented by nil; only rejected data
    /// needs an explicit unavailable marker in the prepared batch.
    nonisolated static func unavailableImageIDs(in captures: [CaptureResult]) -> Set<UUID> {
        var seen = Set<UUID>()
        return Set(captures.compactMap { capture in
            guard seen.insert(capture.id).inserted, let png = capture.pngData else { return nil }
            return validatedPreview(png: png) == nil ? capture.id : nil
        })
    }

    static func matchesBatchIdentity(item: NSPasteboardItem, batch: CaptureBatch) -> Bool {
        item.string(forType: .string) == batch.contextText &&
            item.string(forType: batchIdentifierType) == batch.identity
    }

    static func makeItem(for capture: CaptureResult) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        let context = capture.contextText

        if let png = capture.pngData, let image = image(from: png) {
            let size = displaySize(for: image.size)
            if let rtfd = richDocument(png: png, context: context, size: size) {
                item.setData(rtfd, forType: .rtfd)
            }
            item.setString(htmlDocument(context: context, png: png, size: size), forType: .html)
            item.setData(png, forType: .png)
            if let tiff = image.tiffRepresentation {
                item.setData(tiff, forType: .tiff)
            }
        } else {
            item.setString(htmlDocument(context: context), forType: .html)
        }

        // These are alternative representations of one shot. The destination
        // chooses which representation it can paste; ordering cannot force it
        // to insert an image and text as two separate actions.
        item.setString(context, forType: .string)
        return item
    }

    private struct BatchImage {
        let png: Data
        let size: NSSize
        let preview: NSImage
        let filename: String
        let ordinal: Int
    }

    private static func validatedImages(for batch: CaptureBatch) -> [BatchImage] {
        batch.captures.enumerated().compactMap { offset, capture in
            guard !batch.unavailableImageIDs.contains(capture.id),
                  let png = capture.pngData, let decoded = validatedPreview(png: png) else { return nil }
            let ordinal = offset + 1
            return BatchImage(png: png, size: decoded.size,
                              preview: NSImage(cgImage: decoded.image, size: decoded.size),
                              filename: "NotchShot-\(ordinal)-\(capture.id.uuidString).png", ordinal: ordinal)
        }
    }

    private struct DecodedPreview {
        let image: CGImage
        let size: CGSize
    }

    nonisolated private static func validatedPreview(png: Data) -> DecodedPreview? {
        guard png.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              let source = CGImageSourceCreateWithData(png as CFData, [
                kCGImageSourceShouldCache: false
              ] as CFDictionary),
              CGImageSourceGetStatus(source) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0,
              width <= CaptureImportService.maximumImagePixels / height else { return nil }

        let size = displaySize(for: CGSize(width: width, height: height))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return DecodedPreview(image: thumbnail, size: size)
    }

    private static func richDocument(images: [BatchImage], context: String) -> Data? {
        let document = NSMutableAttributedString(string: "")
        for image in images {
            let wrapper = FileWrapper(regularFileWithContents: image.png)
            wrapper.preferredFilename = image.filename
            wrapper.filename = image.filename
            let attachment = NSTextAttachment(fileWrapper: wrapper)
            attachment.bounds = NSRect(origin: .zero, size: image.size)
            attachment.attachmentCell = NSTextAttachmentCell(imageCell: image.preview)
            document.append(NSAttributedString(attachment: attachment))
            document.append(NSAttributedString(string: "\n\n"))
        }
        document.append(NSAttributedString(string: context, attributes: [.font: NSFont.systemFont(ofSize: 13)]))
        return try? document.data(
            from: NSRange(location: 0, length: document.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
        )
    }

    private static func htmlDocument(images: [BatchImage], context: String) -> String {
        let markup = images.map { image in
            "<img src=\"data:image/png;base64,\(image.png.base64EncodedString())\" width=\"\(Int(image.size.width))\" height=\"\(Int(image.size.height))\" alt=\"NotchShot screenshot \(image.ordinal)\"><br><br>"
        }.joined()
        return """
        <!doctype html><html><head><meta charset="UTF-8"></head><body>\(markup)<pre style="white-space:pre-wrap;overflow-wrap:break-word;font:13px system-ui,sans-serif">\(escapeHTML(context))</pre></body></html>
        """
    }

    private static func image(from png: Data) -> NSImage? {
        let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        guard png.starts(with: signature),
              let bitmap = NSBitmapImageRep(data: png),
              bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else { return nil }
        let image = NSImage(size: NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
        image.addRepresentation(bitmap)
        return image
    }

    nonisolated private static func displaySize(for size: NSSize) -> NSSize {
        let scale = min(1, 640 / size.width, 480 / size.height)
        return NSSize(width: max(1, floor(size.width * scale)), height: max(1, floor(size.height * scale)))
    }

    private static func richDocument(png: Data, context: String, size: NSSize) -> Data? {
        let wrapper = FileWrapper(regularFileWithContents: png)
        wrapper.preferredFilename = "NotchShot.png"
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        attachment.bounds = NSRect(origin: .zero, size: size)
        if let preview = NSImage(data: png) {
            preview.size = size
            attachment.attachmentCell = NSTextAttachmentCell(imageCell: preview)
        }
        let document = NSMutableAttributedString(attachment: attachment)
        document.append(NSAttributedString(
            string: "\n\n" + context,
            attributes: [.font: NSFont.systemFont(ofSize: 13)]
        ))
        return try? document.data(
            from: NSRange(location: 0, length: document.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
        )
    }

    private static func htmlDocument(context: String, png: Data? = nil, size: NSSize = .zero) -> String {
        var image = ""
        if let png {
            image = "<img src=\"data:image/png;base64,\(png.base64EncodedString())\" width=\"\(Int(size.width))\" height=\"\(Int(size.height))\" alt=\"NotchShot screenshot\"><br><br>"
        }
        return """
        <!doctype html><html><head><meta charset="UTF-8"></head><body>\(image)<pre style="white-space:pre-wrap;overflow-wrap:break-word;font:13px system-ui,sans-serif">\(escapeHTML(context))</pre></body></html>
        """
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
