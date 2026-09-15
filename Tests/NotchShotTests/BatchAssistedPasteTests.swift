// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class BatchAssistedPasteTests: XCTestCase {
    @MainActor
    func testThreeImagesPasteInOrderThenCombinedContextAndRestoreEveryRichRepresentation() async throws {
        let fixture = try makeFixture()
        let originals = fixture.representations()
        XCTAssertTrue(fixture.arm())
        XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
        try await fixture.waitForImageCount(1)
        try await fixture.advanceToImageCount(2)
        try await fixture.advanceToImageCount(3)
        try await fixture.advanceToContext()

        XCTAssertEqual(fixture.environment.posts.compactMap(\.png), fixture.batch.captures.compactMap(\.pngData))
        XCTAssertEqual(fixture.environment.posts.map(\.target), Array(repeating: fixture.environment.target!, count: 4))
        XCTAssertEqual(fixture.environment.targetReadCount, 4, "Re-query the original field before every image and the combined text.")
        for post in fixture.environment.posts.prefix(3) {
            XCTAssertNil(post.text)
            XCTAssertNil(post.rtfd)
            XCTAssertNil(post.tiff, "A batch must not retain a decoded TIFF for each screenshot.")
        }
        XCTAssertNil(fixture.environment.posts.last?.png)
        XCTAssertEqual(fixture.environment.posts.last?.text, fixture.batch.contextText)
        XCTAssertEqual(fixture.results, [.eventsSent])

        try await fixture.restore()
        XCTAssertEqual(fixture.representations(), originals)
        XCTAssertFalse(fixture.service.isPasting)
        XCTAssertFalse(fixture.service.isArmed)
        XCTAssertFalse(fixture.emit(.paste(isRepeat: false)), "Only one physical gesture is assisted.")
        XCTAssertTrue(fixture.environment.fallbacks.isEmpty)
    }

    @MainActor
    func testMixedBatchSkipsTextOnlyAndCorruptImagesButIncludesEveryShotsContext() async throws {
        let fixture = try makeFixture(imageKinds: [.valid, .textOnly, .corrupt, .valid])
        XCTAssertTrue(fixture.arm())
        XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
        try await fixture.waitForImageCount(1)
        try await fixture.advanceToImageCount(2)
        try await fixture.advanceToContext()

        XCTAssertEqual(fixture.environment.posts.compactMap(\.png), [fixture.batch.captures[0].pngData!, fixture.batch.captures[3].pngData!])
        XCTAssertEqual(fixture.environment.posts.last?.text, fixture.batch.contextText)
        for capture in fixture.batch.captures {
            XCTAssertTrue(fixture.environment.posts.last?.text?.contains(capture.accessibilityText) == true)
        }
        try await fixture.restore()
    }

    @MainActor
    func testTextOnlyBatchUsesOrdinaryPasteWithoutTakingTheGestureOrChangingClipboard() throws {
        let fixture = try makeFixture(imageKinds: [.textOnly, .textOnly])
        let originals = fixture.representations()
        let changeCount = fixture.clipboard.changeCount
        XCTAssertFalse(fixture.arm())
        XCTAssertFalse(fixture.emit(.paste(isRepeat: false)))
        XCTAssertEqual(fixture.clipboard.changeCount, changeCount)
        XCTAssertEqual(fixture.representations(), originals)
        XCTAssertEqual(fixture.environment.startCount, 0)
    }

    @MainActor
    func testDifferentBatchIdentityOrContextCannotArmEvenWhenSomeImagesMatch() throws {
        for mutation in 0..<4 {
            let fixture = try makeFixture()
            var captures = fixture.batch.captures
            if mutation == 0 { captures[0].id = UUID() }
            if mutation == 1 { captures.reverse() }
            if mutation == 2 { captures[1].accessibilityText = "A different context" }
            if mutation == 3 { captures[2].pngData = captures[0].pngData }
            let changed = CaptureBatch(captures: captures, contextStyle: fixture.batch.contextStyle)
            let originals = fixture.representations()
            let changeCount = fixture.clipboard.changeCount

            XCTAssertFalse(fixture.service.arm(batch: changed, clipboard: fixture.clipboard))
            XCTAssertEqual(fixture.clipboard.changeCount, changeCount)
            XCTAssertEqual(fixture.representations(), originals)
            XCTAssertEqual(fixture.environment.startCount, 0)
        }
    }

    @MainActor
    func testMissingBatchMarkerCannotArmOrdinaryRichTextAsAPendingSelection() throws {
        let fixture = try makeFixture()
        let original = try XCTUnwrap(fixture.clipboard.pasteboardItems?.first)
        let replacement = NSPasteboardItem()
        for type in original.types where type != CaptureClipboardService.batchIdentifierType {
            if let data = original.data(forType: type) { replacement.setData(data, forType: type) }
        }
        fixture.clipboard.clearContents()
        XCTAssertTrue(fixture.clipboard.writeObjects([replacement]))
        XCTAssertFalse(fixture.arm())
        XCTAssertEqual(fixture.environment.startCount, 0)
    }

    @MainActor
    func testClipboardFocusAppOrPermissionChangeBetweenEveryImagePairStopsTheBatch() async throws {
        for completedImages in [1, 2] {
            for mutation in 0..<5 {
                let fixture = try makeFixture()
                XCTAssertTrue(fixture.arm())
                XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
                try await fixture.waitForImageCount(1)
                if completedImages == 2 { try await fixture.advanceToImageCount(2) }
                switch mutation {
                case 0: fixture.copyUnrelatedText("Keep the newer clipboard")
                case 1: fixture.environment.frontmostProcessIdentifier = 99
                case 2: fixture.environment.target = .init(processIdentifier: 42, focusIdentity: "different field")
                case 3: fixture.environment.target = nil
                default: fixture.environment.isAccessibilityTrusted = false
                }
                let changeCount = fixture.clipboard.changeCount
                try await fixture.advanceDelay()
                try await fixture.waitUntil { !fixture.service.isPasting }

                XCTAssertEqual(fixture.environment.posts.count, completedImages)
                XCTAssertTrue(fixture.environment.fallbacks.isEmpty, "Never replay images already sent to the destination.")
                XCTAssertFalse(fixture.service.isArmed)
                if mutation == 0 {
                    XCTAssertEqual(fixture.clipboard.changeCount, changeCount)
                    XCTAssertEqual(fixture.clipboard.string(forType: .string), "Keep the newer clipboard")
                } else {
                    XCTAssertEqual(fixture.clipboard.string(forType: .string), fixture.batch.contextText)
                }
            }
        }
    }

    @MainActor
    func testSuspendedAXRecheckCannotContinueAfterInputClipboardOrAppChanges() async throws {
        // This includes both intermediate image queries and the final text query.
        for completedImages in [1, 2, 3] {
            for mutation in 0..<5 {
                let fixture = try makeFixture()
                XCTAssertTrue(fixture.arm())
                XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
                try await fixture.waitForImageCount(1)
                for count in 2...max(2, completedImages) where count <= completedImages {
                    try await fixture.advanceToImageCount(count)
                }
                fixture.environment.suspendNextQuery = true
                try await fixture.advanceDelay()
                try await fixture.waitUntil { fixture.environment.hasPendingQuery }
                switch mutation {
                case 0: fixture.copyUnrelatedText("New clipboard during AX lookup")
                case 1: XCTAssertFalse(fixture.emit(.pointerDown))
                case 2: XCTAssertFalse(fixture.emit(.keyDown))
                case 3: fixture.environment.frontmostProcessIdentifier = 99
                default: fixture.environment.isAccessibilityTrusted = false
                }
                fixture.environment.resumeQueries()
                try await fixture.waitUntil { !fixture.service.isPasting }
                await Task.yield()
                XCTAssertEqual(fixture.environment.posts.count, completedImages)
                XCTAssertTrue(fixture.environment.fallbacks.isEmpty)
                if mutation == 0 {
                    XCTAssertEqual(fixture.clipboard.string(forType: .string), "New clipboard during AX lookup")
                }
            }
        }
    }

    @MainActor
    func testFailedLaterImagePostingNeverReplaysTheRichBatchOrSendsText() async throws {
        for failedPost in [2, 3] {
            let fixture = try makeFixture()
            let originals = fixture.representations()
            fixture.environment.failPostNumber = failedPost
            XCTAssertTrue(fixture.arm())
            XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
            try await fixture.waitForImageCount(1)
            if failedPost == 3 { try await fixture.advanceToImageCount(2) }
            try await fixture.advanceDelay()
            try await fixture.waitUntil { !fixture.service.isPasting }
            fixture.sleep.resumeAll()
            await Task.yield()

            XCTAssertEqual(fixture.environment.posts.count, failedPost)
            XCTAssertTrue(fixture.environment.posts.allSatisfy { $0.text == nil })
            XCTAssertTrue(fixture.environment.fallbacks.isEmpty)
            XCTAssertEqual(fixture.representations(), originals)
        }
    }

    @MainActor
    func testFailedFirstImageCanReplayTheCompleteRichBatchOnce() async throws {
        let fixture = try makeFixture()
        let originals = fixture.representations()
        fixture.environment.failPostNumber = 1
        XCTAssertTrue(fixture.arm())
        XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
        try await fixture.waitUntil { !fixture.service.isPasting }
        XCTAssertEqual(fixture.environment.posts.count, 1)
        XCTAssertEqual(fixture.environment.fallbacks, [originals])
        XCTAssertEqual(fixture.representations(), originals)
    }

    @MainActor
    func testNewCopyAndArmCannotBeOverwrittenByPreviousSleepingBatch() async throws {
        let fixture = try makeFixture()
        XCTAssertTrue(fixture.arm())
        XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
        try await fixture.waitForImageCount(1)
        try await fixture.advanceToImageCount(2)
        var captures = fixture.batch.captures
        captures.reverse()
        let replacement = CaptureBatch(captures: captures, contextStyle: fixture.batch.contextStyle)
        fixture.clipboard.clearContents()
        XCTAssertTrue(fixture.clipboard.writeObjects([CaptureClipboardService.makeItem(for: replacement)]))
        XCTAssertTrue(fixture.service.arm(batch: replacement, clipboard: fixture.clipboard))
        let originals = fixture.representations()
        let changeCount = fixture.clipboard.changeCount
        try await fixture.advanceDelay()
        await Task.yield()

        XCTAssertEqual(fixture.environment.posts.count, 2)
        XCTAssertTrue(fixture.service.isArmed)
        XCTAssertEqual(fixture.clipboard.changeCount, changeCount)
        XCTAssertEqual(fixture.representations(), originals)
    }

    @MainActor
    func testCopyAfterContextSurvivesDelayedRestoration() async throws {
        let fixture = try makeFixture()
        XCTAssertTrue(fixture.arm())
        XCTAssertTrue(fixture.emit(.paste(isRepeat: false)))
        try await fixture.waitForImageCount(1)
        try await fixture.advanceToImageCount(2)
        try await fixture.advanceToImageCount(3)
        try await fixture.advanceToContext()
        fixture.copyUnrelatedText("Keep the copy after all paste events")
        let changeCount = fixture.clipboard.changeCount
        try await fixture.restore()
        XCTAssertEqual(fixture.clipboard.changeCount, changeCount)
        XCTAssertEqual(fixture.clipboard.string(forType: .string), "Keep the copy after all paste events")
        XCTAssertEqual(fixture.environment.posts.count, 4)
    }

    @MainActor
    private func makeFixture(imageKinds: [BatchImageKind] = [.valid, .valid, .valid]) throws -> BatchPasteFixture {
        let captures = try imageKinds.enumerated().map { index, kind in
            let png: Data?
            switch kind {
            case .valid:
                let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                for x in 0..<2 {
                    for y in 0..<2 { bitmap.setColor(NSColor(deviceRed: CGFloat(index) / 8, green: 0.8, blue: 0.6, alpha: 1), atX: x, y: y) }
                }
                png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            case .textOnly: png = nil
            case .corrupt: png = Data("Not an image".utf8)
            }
            return CaptureResult(appName: "Fixture app \(index + 1)", bundleIdentifier: "com.example.batch.\(index)",
                                 windowTitle: "Window \(index + 1)", pngData: png,
                                 accessibilityText: "Unique context \(index + 1) — 你好 📷")
        }
        let fixture = BatchPasteFixture(batch: CaptureBatch(captures: captures, contextStyle: .full))
        XCTAssertTrue(fixture.clipboard.writeObjects([CaptureClipboardService.makeItem(for: fixture.batch)]))
        addTeardownBlock {
            await MainActor.run {
                fixture.service.stop()
                fixture.sleep.resumeAll()
                fixture.environment.resumeQueries()
                fixture.clipboard.releaseGlobally()
            }
        }
        return fixture
    }
}

private enum BatchImageKind { case valid, textOnly, corrupt }

@MainActor
private final class BatchPasteFixture {
    static let imageDelay: Duration = .milliseconds(111)
    static let restoreDelay: Duration = .milliseconds(222)
    let batch: CaptureBatch
    let clipboard = NSPasteboard(name: .init("NotchShotBatchPasteTests-\(UUID())"))
    let sleep = BatchPasteSleepGate()
    let environment: BatchPasteEnvironment
    let service: AssistedPasteService
    var results: [AssistedPasteResult] = []
    init(batch: CaptureBatch) {
        self.batch = batch
        environment = BatchPasteEnvironment(clipboard: clipboard)
        let sleep = self.sleep
        service = AssistedPasteService(environment: environment, imageDelay: Self.imageDelay,
                                       restoreDelay: Self.restoreDelay, sleep: { try await sleep.wait($0) }, startPolling: false)
        service.onResult = { [weak self] in self?.results.append($0) }
    }
    func arm() -> Bool { service.arm(batch: batch, clipboard: clipboard) }
    func emit(_ event: AssistedPasteEvent) -> Bool { environment.onEvent?(event) ?? false }
    func representations() -> [NSPasteboard.PasteboardType: Data] { environment.representations() }
    func copyUnrelatedText(_ text: String) {
        clipboard.clearContents()
        clipboard.setString(text, forType: .string)
    }
    func waitForImageCount(_ count: Int) async throws {
        try await waitUntil { self.environment.posts.count == count && self.sleep.contains(Self.imageDelay) }
    }
    func advanceToImageCount(_ count: Int) async throws {
        try await advanceDelay()
        try await waitForImageCount(count)
    }
    func advanceToContext() async throws {
        try await advanceDelay()
        try await waitUntil { self.environment.posts.last?.text != nil && self.sleep.contains(Self.restoreDelay) }
    }
    func advanceDelay() async throws {
        try await waitUntil { self.sleep.contains(Self.imageDelay) }
        sleep.resume(Self.imageDelay)
        await Task.yield()
    }
    func restore() async throws {
        try await waitUntil { self.sleep.contains(Self.restoreDelay) }
        sleep.resume(Self.restoreDelay)
        try await waitUntil { !self.service.isPasting }
    }
    func waitUntil(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<300 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for a controlled batch paste phase.", file: file, line: line)
    }
}

@MainActor
private final class BatchPasteSleepGate {
    private var waiters: [(Duration, CheckedContinuation<Void, Error>)] = []
    func wait(_ duration: Duration) async throws {
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { waiters.append((duration, $0)) }
        try Task.checkCancellation()
    }
    func contains(_ duration: Duration) -> Bool { waiters.contains { $0.0 == duration } }
    func resume(_ duration: Duration) {
        guard let index = waiters.firstIndex(where: { $0.0 == duration }) else { return }
        waiters.remove(at: index).1.resume()
    }
    func resumeAll() {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.1.resume() }
    }
}

@MainActor
private final class BatchPasteEnvironment: AssistedPasteEnvironment {
    struct Post {
        let target: AssistedPasteTarget
        let png: Data?
        let tiff: Data?
        let text: String?
        let rtfd: Data?
    }
    var onEvent: ((AssistedPasteEvent) -> Bool)?
    var isAccessibilityTrusted = true
    var frontmostProcessIdentifier: pid_t? = 42
    var target: AssistedPasteTarget? = .init(processIdentifier: 42, focusIdentity: "fixture-window/fixture-field")
    var suspendNextQuery = false
    var failPostNumber: Int?
    private(set) var posts: [Post] = []
    private(set) var fallbacks: [[NSPasteboard.PasteboardType: Data]] = []
    private(set) var targetReadCount = 0
    private(set) var startCount = 0
    private var pendingQueries: [(AssistedPasteTarget?, CheckedContinuation<AssistedPasteTarget?, Never>)] = []
    var hasPendingQuery: Bool { !pendingQueries.isEmpty }
    let clipboard: NSPasteboard
    init(clipboard: NSPasteboard) { self.clipboard = clipboard }
    func startMonitoring() -> Bool { startCount += 1; return true }
    func stopMonitoring() {}
    func currentTarget() async -> AssistedPasteTarget? {
        targetReadCount += 1
        guard suspendNextQuery else { return target }
        suspendNextQuery = false
        let snapshot = target
        return await withCheckedContinuation { pendingQueries.append((snapshot, $0)) }
    }
    func resumeQueries() {
        let pending = pendingQueries
        pendingQueries.removeAll()
        pending.forEach { $0.1.resume(returning: $0.0) }
    }
    func representations() -> [NSPasteboard.PasteboardType: Data] {
        guard let item = clipboard.pasteboardItems?.first else { return [:] }
        return Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
    }
    func postPaste(to target: AssistedPasteTarget) -> Bool {
        // NSPasteboard.data(forType:) can synthesize TIFF from a PNG. Inspect
        // declared types so the spy does not itself create the allocation tested.
        let explicitTIFF = clipboard.pasteboardItems?.first.flatMap { item in
            item.types.contains(.tiff) ? item.data(forType: .tiff) : nil
        }
        posts.append(Post(target: target, png: clipboard.data(forType: .png), tiff: explicitTIFF,
                          text: clipboard.string(forType: .string), rtfd: clipboard.data(forType: .rtfd)))
        return posts.count != failPostNumber
    }
    func postFallbackPaste(to processIdentifier: pid_t) -> Bool {
        fallbacks.append(representations())
        return true
    }
}
