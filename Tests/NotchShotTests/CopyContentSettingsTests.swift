// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class CopyContentSettingsTests: XCTestCase {
    @MainActor
    func testDefaultAndUnknownPreferenceUseScreenshotAndTree() {
        let f = fixture()
        defer { f.store.stop() }
        XCTAssertEqual(f.store.copyContent, .screenshotAndTree)

        f.preferences.set("future-mode", forKey: "copyContent")
        let restored = CaptureStore(preferences: f.preferences, clipboard: f.board, assistedPaste: ContentPasteSpy())
        defer { restored.stop() }
        XCTAssertEqual(restored.copyContent, .screenshotAndTree)
    }

    @MainActor
    func testEveryChoicePersistsAndChangingItCancelsPendingAssistance() throws {
        let f = fixture()
        defer { f.store.stop() }
        let capture = try shot("Preference")
        f.store.captures = [capture]
        f.store.pasteImageThenText = true
        XCTAssertTrue(f.store.copyCapture(capture.id))
        XCTAssertEqual(f.paste.armedCaptures, [capture.id])

        for content in [CaptureCopyContent.imageOnly, .treeOnly, .screenshotAndTree] {
            let cancellations = f.paste.cancelCount
            let clipboardVersion = f.board.changeCount
            f.store.copyContent = content
            XCTAssertGreaterThan(f.paste.cancelCount, cancellations)
            XCTAssertEqual(f.board.changeCount, clipboardVersion, "Changing a preference must not recopy a previous shot.")
            XCTAssertEqual(f.preferences.string(forKey: "copyContent"), content.rawValue)
            let restored = CaptureStore(preferences: f.preferences, clipboard: f.board, assistedPaste: ContentPasteSpy())
            XCTAssertEqual(restored.copyContent, content)
            restored.stop()
        }
    }

    @MainActor
    func testHoverAndPrimaryCopyUseSelectedContentWithoutChangingDetailSelection() throws {
        let f = fixture()
        defer { f.store.stop() }
        let detail = try shot("Detail")
        let hovered = try shot("Hovered")
        f.store.captures = [detail, hovered]
        f.store.selectedID = detail.id
        f.store.pasteImageThenText = true

        for content in [CaptureCopyContent.screenshotAndTree, .imageOnly, .treeOnly] {
            f.store.copyContent = content
            XCTAssertTrue(f.store.copyShelfShot(hovered.id))
            assertClipboard(f.board, contains: hovered, content: content)
            XCTAssertEqual(f.store.selectedID, detail.id)
            f.store.copyContext()
            assertClipboard(f.board, contains: detail, content: content)
        }
        XCTAssertEqual(f.paste.armedCaptures, [hovered.id, detail.id], "Single-content choices never arm a second paste stage.")
        XCTAssertEqual(f.sound.plays, 6)
    }

    @MainActor
    func testAutomaticCopyUsesEachModeOnceAndOnlyCombinedModeArmsAssistance() throws {
        let f = fixture()
        defer { f.store.stop() }
        f.store.autoCopyCapture = true
        f.store.pasteImageThenText = true
        var combinedID: UUID?
        for content in [CaptureCopyContent.screenshotAndTree, .imageOnly, .treeOnly] {
            f.store.copyContent = content
            let capture = try shot(content.rawValue)
            f.store.autoCopyCompletedCapture(capture)
            assertClipboard(f.board, contains: capture, content: content)
            let clipboardVersion = f.board.changeCount
            f.store.autoCopyCompletedCapture(capture)
            XCTAssertEqual(f.board.changeCount, clipboardVersion)
            if content == .screenshotAndTree { combinedID = capture.id }
        }
        XCTAssertEqual(f.paste.armedCaptures, [try XCTUnwrap(combinedID)])
        XCTAssertEqual(f.sound.plays, 3)
    }

    @MainActor
    func testBatchModesPreserveOrderedImagesOrExactTreesAndOnlyCombinedArms() async throws {
        let f = fixture()
        defer { f.store.stop() }
        let shots = try [shot("First", color: .systemMint), shot("Second", color: .systemOrange)]
        f.store.captures = shots
        f.store.batchContextStyle = .full
        f.store.pasteImageThenText = true
        f.store.selectAllShelfShots()
        let batch = try await preparedBatch(f.store)

        f.store.copyContent = .screenshotAndTree
        XCTAssertTrue(f.store.copyShelfSelection())
        XCTAssertEqual(f.board.string(forType: .string), batch.contextText)
        XCTAssertEqual(try attachments(f.board), shots.compactMap(\.pngData))

        f.store.copyContent = .imageOnly
        XCTAssertTrue(f.store.copyShelfSelection())
        XCTAssertNil(f.board.string(forType: .string))
        XCTAssertEqual(try attachments(f.board), shots.compactMap(\.pngData))
        XCTAssertFalse(f.store.statusNotice?.message.contains("tree") == true)
        XCTAssertTrue(f.store.statusNotice?.message.contains("2 screenshots") == true)

        f.store.copyContent = .treeOnly
        XCTAssertTrue(f.store.copyShelfSelection())
        XCTAssertEqual(f.board.string(forType: .string), CaptureClipboardService.treeText(for: batch))
        XCTAssertTrue(f.board.string(forType: .string)?.hasPrefix("# NotchShot — 2 trees · No images") == true)
        for capture in shots {
            XCTAssertTrue(f.board.string(forType: .string)?.contains(capture.clipboardBody) == true)
        }
        XCTAssertNil(f.board.data(forType: .png))
        XCTAssertNil(f.board.data(forType: .tiff))
        XCTAssertNil(f.board.data(forType: .rtfd))
        XCTAssertTrue(f.store.statusNotice?.message.contains("Accessibility trees") == true)
        XCTAssertEqual(f.paste.armedBatches, [shots.map(\.id)])
        XCTAssertEqual(f.sound.plays, 3)
    }

    @MainActor
    func testImageOnlyBatchReportsOmittedImagesWithoutClaimingTheirTextWasCopied() async throws {
        let f = fixture()
        defer { f.store.stop() }
        let available = try shot("Available")
        var missing = try shot("Missing")
        missing.pngData = nil
        var corrupt = try shot("Corrupt")
        corrupt.pngData = Data("not an image".utf8)
        f.store.captures = [available, missing, corrupt]
        f.store.selectAllShelfShots()
        _ = try await preparedBatch(f.store)
        f.store.copyContent = .imageOnly

        XCTAssertTrue(f.store.copyShelfSelection())
        XCTAssertEqual(f.board.data(forType: .png), available.pngData)
        XCTAssertNil(f.board.string(forType: .string))
        let notice = try XCTUnwrap(f.store.statusNotice)
        XCTAssertEqual(notice.kind, .success)
        XCTAssertTrue(notice.message.contains("1 screenshot copied"))
        XCTAssertTrue(notice.message.contains("Skipped shots 2, 3"))
        XCTAssertFalse(notice.message.contains("text is included"))
    }

    @MainActor
    func testMissingImageManualAndAutomaticCopyPreserveClipboardAndStaySilentAndOpen() async throws {
        let f = fixture()
        defer { f.store.stop() }
        var missing = try shot("Missing")
        missing.pngData = nil
        var corrupt = try shot("Corrupt")
        corrupt.pngData = Data("invalid".utf8)
        f.store.captures = [missing, corrupt]
        f.store.copyContent = .imageOnly
        f.store.pasteImageThenText = true
        f.store.autoCopyCapture = true
        f.store.autoCollapseEnabled = false
        f.store.isExpanded = true
        f.board.setString("Existing clipboard", forType: .string)
        let clipboardVersion = f.board.changeCount

        for capture in [missing, corrupt] {
            XCTAssertFalse(f.store.copyCapture(capture.id))
            f.store.autoCopyCompletedCapture(capture)
            XCTAssertEqual(f.board.changeCount, clipboardVersion)
            XCTAssertEqual(f.board.string(forType: .string), "Existing clipboard")
            XCTAssertEqual(f.store.statusNotice?.kind, .error)
            XCTAssertTrue(f.store.statusNotice?.message.contains("Screen Recording") == true)
        }
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertTrue(f.store.isExpanded)
        XCTAssertEqual(f.sound.plays, 0)
        XCTAssertTrue(f.paste.armedCaptures.isEmpty)
    }

    @MainActor
    func testBatchWithNoImageDoesNotOverwriteOrConfirm() async throws {
        let f = fixture()
        defer { f.store.stop() }
        var missing = try shot("Missing")
        missing.pngData = nil
        f.store.captures = [missing]
        f.store.selectAllShelfShots()
        _ = try await preparedBatch(f.store)
        f.store.copyContent = .imageOnly
        f.store.pasteImageThenText = true
        f.board.setString("Previous clipboard", forType: .string)
        let clipboardVersion = f.board.changeCount

        XCTAssertFalse(f.store.copyShelfSelection())
        XCTAssertEqual(f.board.changeCount, clipboardVersion)
        XCTAssertEqual(f.board.string(forType: .string), "Previous clipboard")
        XCTAssertEqual(f.sound.plays, 0)
        XCTAssertTrue(f.paste.armedBatches.isEmpty)
        XCTAssertTrue(f.store.statusNotice?.message.contains("choose AX tree in Settings") == true)
    }

    @MainActor
    func testExplicitCopyButtonsKeepTheirMeaningAndTreeIncludesCompletenessNotice() throws {
        let f = fixture()
        defer { f.store.stop() }
        var capture = try shot("Incomplete")
        capture.accessibilityTreeIncomplete = true
        f.store.captures = [capture]
        f.store.selectedID = capture.id
        f.store.copyContent = .imageOnly
        f.store.pasteImageThenText = true

        f.store.copyTree()
        XCTAssertEqual(f.board.string(forType: .string), capture.clipboardText)
        XCTAssertTrue(f.board.string(forType: .string)?.hasPrefix(CapturedContext.opening + "\n[Accessibility tree is incomplete:") == true)
        XCTAssertNil(f.board.data(forType: .png))
        f.store.copyText()
        XCTAssertTrue(f.board.string(forType: .string)?.contains(capture.accessibilityText) == true)
        XCTAssertTrue(f.board.string(forType: .string)?.contains(capture.ocrText) == true)

        f.store.copyContent = .treeOnly
        f.store.copyImage()
        XCTAssertEqual(f.board.data(forType: .png), capture.pngData)
        XCTAssertNil(f.board.string(forType: .string))
        XCTAssertTrue(f.paste.armedCaptures.isEmpty)
    }

    @MainActor
    private func assertClipboard(_ board: NSPasteboard, contains capture: CaptureResult, content: CaptureCopyContent,
                                 file: StaticString = #filePath, line: UInt = #line) {
        switch content {
        case .screenshotAndTree:
            XCTAssertEqual(board.data(forType: .png), capture.pngData, file: file, line: line)
            XCTAssertEqual(board.string(forType: .string), capture.clipboardText, file: file, line: line)
            XCTAssertNotNil(board.data(forType: .rtfd), file: file, line: line)
        case .imageOnly:
            XCTAssertEqual(board.data(forType: .png), capture.pngData, file: file, line: line)
            XCTAssertNil(board.string(forType: .string), file: file, line: line)
        case .treeOnly:
            XCTAssertEqual(board.string(forType: .string), capture.clipboardText, file: file, line: line)
            XCTAssertNil(board.data(forType: .png), file: file, line: line)
            XCTAssertNil(board.data(forType: .tiff), file: file, line: line)
            XCTAssertNil(board.data(forType: .rtfd), file: file, line: line)
        }
    }

    @MainActor
    private func attachments(_ board: NSPasteboard) throws -> [Data] {
        let data = try XCTUnwrap(board.data(forType: .rtfd))
        let document = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
        var result: [Data] = []
        document.enumerateAttribute(.attachment, in: NSRange(location: 0, length: document.length)) { attachment, _, _ in
            if let data = (attachment as? NSTextAttachment)?.fileWrapper?.regularFileContents { result.append(data) }
        }
        return result
    }

    @MainActor
    private func preparedBatch(_ store: CaptureStore) async throws -> CaptureBatch {
        let deadline = ContinuousClock.now + .seconds(2)
        while store.isPreparingBatch && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(store.isPreparingBatch, "Batch preparation exceeded the bounded wait.")
        return try XCTUnwrap(store.selectedBatch)
    }

    @MainActor
    private func shot(_ name: String, color: NSColor = .systemMint) throws -> CaptureResult {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for x in 0..<2 { for y in 0..<2 { bitmap.setColor(color, atX: x, y: y) } }
        return CaptureResult(appName: name, bundleIdentifier: "test.copy-content", windowTitle: "Window \(name)",
                             pngData: try XCTUnwrap(bitmap.representation(using: .png, properties: [:])),
                             axTree: [AXNode(id: 1, role: "AXButton", roleDescription: "button", title: "Submit \(name)")],
                             accessibilityText: "Flat source \(name)", ocrText: "OCR source \(name)")
    }

    @MainActor
    private func fixture() -> (store: CaptureStore, preferences: UserDefaults, board: NSPasteboard,
                               paste: ContentPasteSpy, sound: ContentCopySound) {
        let suite = "CopyContentSettingsTests.\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        let board = NSPasteboard.withUniqueName()
        let paste = ContentPasteSpy()
        let sound = ContentCopySound()
        let store = CaptureStore(preferences: preferences, captureSound: ContentCaptureSound(), clipboard: board,
                                 copySound: sound, copyCollapseDelay: .milliseconds(20), assistedPaste: paste)
        addTeardownBlock {
            preferences.removePersistentDomain(forName: suite)
            board.releaseGlobally()
        }
        return (store, preferences, board, paste, sound)
    }
}

@MainActor
private final class ContentPasteSpy: AssistedPasteServing {
    var onResult: ((AssistedPasteResult) -> Void)?
    var cancelCount = 0
    var armedCaptures: [UUID] = []
    var armedBatches: [[UUID]] = []
    func arm(capture: CaptureResult, clipboard: NSPasteboard) -> Bool {
        armedCaptures.append(capture.id)
        return true
    }
    func arm(batch: CaptureBatch, clipboard: NSPasteboard) -> Bool {
        armedBatches.append(batch.captures.map(\.id))
        return true
    }
    func cancel() { cancelCount += 1 }
    func stop() { cancel() }
}

@MainActor
private final class ContentCopySound: CopySoundPlaying {
    var plays = 0
    func play() { plays += 1 }
    func setVolume(_ volume: Float) {}
}

@MainActor
private final class ContentCaptureSound: CaptureSoundPlaying {
    func play() {}
}
