// SPDX-License-Identifier: MIT
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Owned values captured during performDragOperation. Never retains a drag
/// pasteboard or asks its source to render an image after the drop has returned.
struct CaptureImportPayload: Sendable {
    let imageData: Data?
    let text: String
    let name: String
    var warnings: [String] = []
}

enum CaptureImportError: LocalizedError {
    case unsupportedDrop
    case inputTooLarge
    case invalidText
    case unavailableLocalFile
    case invalidImage
    case imageTooLarge

    var errorDescription: String? {
        switch self {
        case .unsupportedDrop:
            return "Drop a PNG, JPEG, TIFF, or HEIC image, or plain text. Download image files locally before dropping them."
        case .inputTooLarge:
            return "This drop is larger than 32 MB. Export a smaller image or shorten the accompanying text and try again."
        case .invalidText:
            return "The dropped text isn't valid UTF-8 plain text. Copy it as plain text and try again."
        case .unavailableLocalFile:
            return "The image isn't an available local file. Download it to this Mac, then drag the image file into NotchShot."
        case .invalidImage:
            return "NotchShot couldn't read this image. Export it as PNG or JPEG and try again."
        case .imageTooLarge:
            return "The image exceeds 40 megapixels. Resize it before importing it into NotchShot."
        }
    }
}

@MainActor
enum CaptureImportService {
    nonisolated static let maximumInputBytes = 32 * 1_024 * 1_024
    nonisolated static let maximumImagePixels = 40_000_000

    /// Register only raster representations we can validate without NSImage
    /// decoding, plus existing file URLs and UTF-8 plain text. This also covers
    /// NSImage drag writers, which normally publish a TIFF representation.
    static let readableTypes: [NSPasteboard.PasteboardType] = imageTypes + [.fileURL, .string]
    private static let imageTypes: [NSPasteboard.PasteboardType] = [
        .png, .tiff, .init(UTType.jpeg.identifier), .init(UTType.heic.identifier), .init(UTType.heif.identifier)
    ]
    private nonisolated static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "tif", "tiff", "heic", "heif"]

    /// Hover does not request image bytes, decode images, read file contents, or
    /// run OCR. The actual drop validates file availability, sizes and formats.
    static func canImport(_ pasteboard: NSPasteboard) -> Bool {
        (pasteboard.pasteboardItems ?? []).contains { isImageItem($0) || isPlainTextItem($0) }
    }

    /// Call synchronously inside the native drop callback. All image bytes,
    /// including local file contents, are copied before the source can remove or
    /// replace temporary drag files. Only decoding and OCR remain asynchronous.
    static func snapshot(from pasteboard: NSPasteboard) throws -> CaptureImportPayload {
        let items = pasteboard.pasteboardItems ?? []
        let imageItems = items.filter(isImageItem)
        // Select one card first. Pasteboard-wide data/string lookup can choose
        // different items for different formats, mixing one image with another
        // item's context. All reads below use this exact item.
        guard let item = imageItems.first ?? items.first(where: isPlainTextItem) else {
            throw CaptureImportError.unsupportedDrop
        }
        let fileURL = fileURL(in: item)
        let localURL = fileURL.flatMap { supportedFileURL($0) ? $0 : nil }
        let warnings = items.count > 1
            ? [imageItems.isEmpty
                ? "This drop contained multiple items; only the first supported text item was imported."
                : "This drop contained multiple items; only the first supported image and its accompanying text were imported."]
            : []
        var text = ""
        if let textData = item.data(forType: .string) {
            guard textData.count <= maximumInputBytes else { throw CaptureImportError.inputTooLarge }
            guard let decoded = String(data: textData, encoding: .utf8) else { throw CaptureImportError.invalidText }
            text = decoded
            // Finder sometimes publishes the file path as a plain-text alternate
            // representation. That is a filename, not user-supplied context.
            if let fileURL, text == fileURL.absoluteString || text == fileURL.path { text = "" }
        }

        let textBytes = text.utf8.count
        for type in imageTypes where item.types.contains(type) {
            guard let data = item.data(forType: type) else { continue }
            guard data.count <= maximumInputBytes - textBytes else { throw CaptureImportError.inputTooLarge }
            guard !data.isEmpty else { throw CaptureImportError.invalidImage }
            return CaptureImportPayload(imageData: data, text: text,
                                        name: localURL?.lastPathComponent ?? "Imported Appshot",
                                        warnings: warnings)
        }

        if let localURL {
            // Metadata is checked before a bounded read. No image decode occurs
            // during the callback, and no file URL survives into async import.
            let bytes = try readLocalFile(localURL, byteBudget: maximumInputBytes - textBytes)
            return CaptureImportPayload(imageData: bytes, text: text,
                                        name: localURL.lastPathComponent, warnings: warnings)
        }
        // Unsupported file drops must not silently turn Finder's filename into
        // an apparent appshot. An ordinary URL string can still be imported as
        // text; no URL is ever fetched.
        guard !item.types.contains(.fileURL), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CaptureImportError.unsupportedDrop
        }
        return CaptureImportPayload(imageData: nil, text: text, name: "Imported Appshot", warnings: warnings)
    }

    static func importCapture(from pasteboard: NSPasteboard) async throws -> CaptureResult {
        let payload = try snapshot(from: pasteboard)
        return try await importCapture(payload: payload)
    }

    static func importCapture(payload: CaptureImportPayload) async throws -> CaptureResult {
        guard payload.text.utf8.count <= maximumInputBytes else { throw CaptureImportError.inputTooLarge }
        var capture = CaptureResult(appName: payload.name, bundleIdentifier: "",
                                    windowTitle: payload.name, windowID: nil, pngData: nil)
        capture.importedText = payload.text
        capture.warnings = payload.warnings
        if payload.imageData != nil {
            let decoded = try await Task.detached(priority: .userInitiated) {
                try decodeImage(payload: payload)
            }.value
            capture.pngData = decoded.pngData
            capture.warnings += decoded.warnings
            capture.warnings.append("Imported image: no accessibility tree was supplied. The image and any accompanying plain text were preserved separately.")
            if payload.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                do {
                    capture.ocrText = try await OCRService.recognizeText(in: decoded.image)
                    capture.warnings.append("Text was recognized locally from the imported image with OCR; it is not an accessibility tree.")
                } catch {
                    capture.warnings.append("The image was imported, but local text recognition failed. Try another import or add plain-text context.")
                }
            }
        } else {
            guard !payload.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CaptureImportError.unsupportedDrop
            }
            capture.warnings.append("Imported plain text: no screenshot or structured accessibility tree was supplied.")
        }
        return capture
    }

    private struct DecodedImage: @unchecked Sendable {
        let image: CGImage
        let pngData: Data
        var warnings: [String]
    }

    private nonisolated static func decodeImage(payload: CaptureImportPayload) throws -> DecodedImage {
        let byteBudget = maximumInputBytes - payload.text.utf8.count
        let data: Data
        if let bytes = payload.imageData {
            guard bytes.count <= byteBudget else { throw CaptureImportError.inputTooLarge }
            data = bytes
        } else {
            throw CaptureImportError.invalidImage
        }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              let sourceType = CGImageSourceGetType(source), supportedImageType(sourceType as String),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { throw CaptureImportError.invalidImage }
        try validatePixelDimensions(width: width, height: height)

        // Decode only after header dimensions pass the cap. The transform applies
        // JPEG/HEIC orientation while keeping the original pixel dimensions.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw CaptureImportError.invalidImage
        }
        try validatePixelDimensions(width: image.width, height: image.height)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw CaptureImportError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CaptureImportError.invalidImage }
        var notes: [String] = []
        if CGImageSourceGetCount(source) > 1 {
            notes.append("Only the first image or page of this multi-image file was imported.")
        }
        return DecodedImage(image: image, pngData: output as Data, warnings: notes)
    }

    nonisolated static func validatePixelDimensions(width: Int, height: Int) throws {
        guard width > 0, height > 0 else { throw CaptureImportError.invalidImage }
        // Division avoids overflow from hostile or corrupt image dimensions.
        guard width <= maximumImagePixels / height else { throw CaptureImportError.imageTooLarge }
    }

    private nonisolated static func supportedImageType(_ identifier: String) -> Bool {
        guard let type = UTType(identifier) else { return false }
        return [UTType.png, .jpeg, .tiff, .heic, .heif].contains { type.conforms(to: $0) }
    }

    private nonisolated static func supportedFileURL(_ url: URL) -> Bool {
        url.isFileURL && (url.host == nil || url.host == "" || url.host == "localhost")
            && imageExtensions.contains(url.pathExtension.lowercased())
    }

    private static func fileURL(in item: NSPasteboardItem) -> URL? {
        item.string(forType: .fileURL).flatMap(URL.init(string:))
    }

    private static func isImageItem(_ item: NSPasteboardItem) -> Bool {
        if imageTypes.contains(where: item.types.contains) { return true }
        return fileURL(in: item).map(supportedFileURL) ?? false
    }

    private static func isPlainTextItem(_ item: NSPasteboardItem) -> Bool {
        item.types.contains(.string) && !item.types.contains(.fileURL)
    }

    private nonisolated static func validateLocalFile(_ url: URL, byteBudget: Int) throws {
        guard supportedFileURL(url) else { throw CaptureImportError.unavailableLocalFile }
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey, .fileSizeKey,
                                                         .volumeIsLocalKey, .isUbiquitousItemKey,
                                                         .ubiquitousItemDownloadingStatusKey])
            guard values.isRegularFile == true, values.isReadable == true, values.volumeIsLocal == true,
                  let size = values.fileSize else { throw CaptureImportError.unavailableLocalFile }
            if values.isUbiquitousItem == true,
               values.ubiquitousItemDownloadingStatus != .current,
               values.ubiquitousItemDownloadingStatus != .downloaded {
                throw CaptureImportError.unavailableLocalFile
            }
            guard size <= byteBudget else { throw CaptureImportError.inputTooLarge }
        } catch let error as CaptureImportError {
            throw error
        } catch {
            throw CaptureImportError.unavailableLocalFile
        }
    }

    private nonisolated static func readLocalFile(_ url: URL, byteBudget: Int) throws -> Data {
        let scopedAccess = url.startAccessingSecurityScopedResource()
        defer { if scopedAccess { url.stopAccessingSecurityScopedResource() } }
        try validateLocalFile(url, byteBudget: byteBudget)
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var data = Data()
            // Bound the read itself, including a file that grows after metadata
            // validation. No temporary files or network requests are created.
            while data.count <= byteBudget {
                let remaining = byteBudget + 1 - data.count
                guard let chunk = try handle.read(upToCount: min(1_024 * 1_024, remaining)), !chunk.isEmpty else { break }
                data.append(chunk)
            }
            guard data.count <= byteBudget else { throw CaptureImportError.inputTooLarge }
            return data
        } catch let error as CaptureImportError {
            throw error
        } catch {
            throw CaptureImportError.unavailableLocalFile
        }
    }
}
