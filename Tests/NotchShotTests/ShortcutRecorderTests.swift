// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class ShortcutRecorderTests: XCTestCase {
    @MainActor
    func testCommandEquivalentRecordsOnceAndEndsAfterCandidateCallback() throws {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        var events: [String] = []
        var candidates: [CaptureShortcut] = []
        fixture.button.onRecordingChange = { events.append("recording:\($0)") }
        fixture.button.onRecord = {
            candidates.append($0)
            events.append("candidate")
        }

        fixture.button.beginRecording()
        XCTAssertTrue(fixture.button.isRecording)
        XCTAssertTrue(fixture.window.firstResponder === fixture.button)
        let consumed = fixture.button.performKeyEquivalent(with: try key(code: 40, modifiers: [.command, .option]))

        XCTAssertTrue(consumed, "A recorded Command combination must not continue to an app menu.")
        XCTAssertEqual(candidates, [try XCTUnwrap(CaptureShortcut(keyCode: 40, modifierFlags: [.command, .option]))])
        XCTAssertEqual(events, ["recording:true", "candidate", "recording:false"])
        XCTAssertFalse(fixture.button.isRecording)
    }

    @MainActor
    func testInvalidAndRepeatedKeysStayInRecorderAndEscapeCancels() throws {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        var candidates: [CaptureShortcut] = []
        var message: String?
        fixture.button.onRecord = { candidates.append($0) }
        fixture.button.onValidationChange = { message = $0 }
        fixture.button.beginRecording()

        XCTAssertTrue(fixture.button.performKeyEquivalent(with: try key(code: 0, modifiers: [])))
        XCTAssertTrue(fixture.button.isRecording)
        XCTAssertNotNil(message)
        fixture.button.keyDown(with: try key(code: 0, modifiers: .shift))
        XCTAssertTrue(fixture.button.isRecording)
        XCTAssertTrue(candidates.isEmpty)
        fixture.button.keyDown(with: try key(code: 40, modifiers: [.command, .option], isRepeat: true))
        XCTAssertTrue(fixture.button.isRecording)
        XCTAssertTrue(candidates.isEmpty)

        XCTAssertTrue(fixture.button.performKeyEquivalent(with: try key(code: 53, modifiers: [])))
        XCTAssertFalse(fixture.button.isRecording)
        XCTAssertNil(message)
        XCTAssertTrue(candidates.isEmpty, "Escape must cancel rather than replace the shortcut.")
    }

    @MainActor
    func testTabCancelsAndMovesFocusInBothDirections() throws {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        var candidates: [CaptureShortcut] = []
        fixture.button.onRecord = { candidates.append($0) }
        fixture.button.beginRecording()
        fixture.button.keyDown(with: try key(code: 48, modifiers: []))
        XCTAssertFalse(fixture.button.isRecording)
        XCTAssertTrue(fixture.window.firstResponder === fixture.after)

        fixture.button.beginRecording()
        fixture.button.keyDown(with: try key(code: 48, modifiers: .shift))
        XCTAssertFalse(fixture.button.isRecording)
        XCTAssertTrue(fixture.window.firstResponder === fixture.before)
        XCTAssertTrue(candidates.isEmpty)
    }

    @MainActor
    func testFocusLossAndWindowDeactivationCancelWithoutChangingShortcut() {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        var states: [Bool] = []
        var candidates: [CaptureShortcut] = []
        fixture.button.onRecordingChange = { states.append($0) }
        fixture.button.onRecord = { candidates.append($0) }

        fixture.button.beginRecording()
        fixture.window.makeFirstResponder(fixture.after)
        XCTAssertFalse(fixture.button.isRecording)
        fixture.button.beginRecording()
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: fixture.window)
        XCTAssertFalse(fixture.button.isRecording)
        fixture.button.beginRecording()
        fixture.button.endRecording(notify: false)
        XCTAssertFalse(fixture.button.isRecording)
        XCTAssertEqual(states, [true, false, true, false, true], "An external false binding should not send a duplicate state change.")
        XCTAssertTrue(candidates.isEmpty)
    }

    @MainActor
    private func makeFixture() -> (window: RecorderTestWindow, button: ShortcutRecorderButton, before: RecorderTestFocusView, after: RecorderTestFocusView) {
        _ = NSApplication.shared
        // Never order this window onscreen or take focus from the live app.
        let window = RecorderTestWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.autorecalculatesKeyViewLoop = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        let before = RecorderTestFocusView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        let button = ShortcutRecorderButton(frame: NSRect(x: 30, y: 0, width: 200, height: 32))
        let after = RecorderTestFocusView(frame: NSRect(x: 240, y: 0, width: 20, height: 20))
        [before, button, after].forEach(content.addSubview)
        window.contentView = content
        before.nextKeyView = button
        button.nextKeyView = after
        after.nextKeyView = before
        return (window, button, before, after)
    }

    @MainActor
    private func key(code: UInt16, modifiers: NSEvent.ModifierFlags, isRepeat: Bool = false) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "k", charactersIgnoringModifiers: "k",
            isARepeat: isRepeat, keyCode: code
        ))
    }
}

private final class RecorderTestWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override func makeKey() { /* Hidden native fixture: do not change live app focus. */ }
}

private final class RecorderTestFocusView: NSView {
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
}
