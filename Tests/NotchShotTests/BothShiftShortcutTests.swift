// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class BothShiftShortcutTests: XCTestCase {
    private typealias Key = BothShiftChordDetector.ShiftKey

    private func flags(_ keys: Set<Key>, extra: NSEvent.ModifierFlags = []) -> NSEvent.ModifierFlags {
        var raw = extra.rawValue
        if !keys.isEmpty { raw |= NSEvent.ModifierFlags.shift.rawValue }
        if keys.contains(.left) { raw |= 0x00000002 }
        if keys.contains(.right) { raw |= 0x00000004 }
        return NSEvent.ModifierFlags(rawValue: raw)
    }

    private func change(_ detector: inout BothShiftChordDetector, _ key: Key, held: Set<Key>, extra: NSEvent.ModifierFlags = [], mouse: Bool = false) -> Bool {
        detector.shiftChanged(key: key, flags: flags(held, extra: extra), hasPressedMouseButtons: mouse)
    }

    func testLeftThenRightFiresWhenSecondShiftIsPressed() {
        var detector = BothShiftChordDetector()
        XCTAssertFalse(change(&detector, .left, held: [.left]))
        XCTAssertTrue(change(&detector, .right, held: [.left, .right]))
    }

    func testRightThenLeftFiresWhenSecondShiftIsPressed() {
        var detector = BothShiftChordDetector()
        XCTAssertFalse(change(&detector, .right, held: [.right]))
        XCTAssertTrue(change(&detector, .left, held: [.left, .right]))
    }

    func testBothKeysMustReleaseBeforeAnotherCapture() {
        for firstRelease in [Key.left, .right] {
            let remaining: Key = firstRelease == .left ? .right : .left
            var detector = BothShiftChordDetector()
            XCTAssertFalse(change(&detector, .left, held: [.left]))
            XCTAssertTrue(change(&detector, .right, held: [.left, .right]))
            XCTAssertFalse(change(&detector, firstRelease, held: [remaining]))
            XCTAssertFalse(change(&detector, firstRelease, held: [.left, .right]))
            XCTAssertFalse(change(&detector, firstRelease, held: [remaining]))
            XCTAssertFalse(change(&detector, remaining, held: []))
            XCTAssertFalse(change(&detector, .right, held: [.right]))
            XCTAssertTrue(change(&detector, .left, held: [.left, .right]))
        }
    }

    func testRepeatedSnapshotsDoNotSynthesizePressesOrRepeatCapture() {
        var detector = BothShiftChordDetector()
        XCTAssertFalse(change(&detector, .left, held: [.left]))
        XCTAssertFalse(change(&detector, .left, held: [.left]))
        XCTAssertFalse(change(&detector, .right, held: [.left]))
        XCTAssertTrue(change(&detector, .right, held: [.left, .right]))
        XCTAssertFalse(change(&detector, .right, held: [.left, .right]))
        XCTAssertFalse(change(&detector, .left, held: [.left, .right]))
    }

    func testDoubleTappingEitherSingleShiftNeverCaptures() {
        for key in [Key.left, .right] {
            var detector = BothShiftChordDetector()
            for _ in 0..<4 {
                XCTAssertFalse(change(&detector, key, held: [key]))
                XCTAssertFalse(change(&detector, key, held: []))
            }
        }
    }

    func testAlternatingShiftKeysWithoutOverlapNeverCaptures() {
        var detector = BothShiftChordDetector()
        for key in [Key.left, .right, .left, .right] {
            XCTAssertFalse(change(&detector, key, held: [key]))
            XCTAssertFalse(change(&detector, key, held: []))
        }
    }

    func testOtherModifierOnEitherPressCancelsUntilBothRelease() {
        let modifiers: [NSEvent.ModifierFlags] = [.command, .option, .control, .function]
        for modifier in modifiers {
            for modifyFirstPress in [true, false] {
                var detector = BothShiftChordDetector()
                XCTAssertFalse(change(&detector, .left, held: [.left], extra: modifyFirstPress ? modifier : []))
                XCTAssertFalse(change(&detector, .right, held: [.left, .right], extra: modifyFirstPress ? [] : modifier))
                XCTAssertFalse(change(&detector, .left, held: [.right]))
                XCTAssertFalse(change(&detector, .left, held: [.left, .right]))
                XCTAssertFalse(change(&detector, .left, held: [.right]))
                XCTAssertFalse(change(&detector, .right, held: []))
                XCTAssertFalse(change(&detector, .left, held: [.left]))
                XCTAssertTrue(change(&detector, .right, held: [.left, .right]))
            }
        }
    }

    func testTypingSelectionAndKeyReleaseCannotCompleteInterruptedChord() {
        var detector = BothShiftChordDetector()
        XCTAssertFalse(change(&detector, .left, held: [.left]))
        detector.cancel(shiftIsDown: true) // Letter or arrow-key keyDown.
        detector.cancel(shiftIsDown: false) // KeyUp with stale modifier flags.
        XCTAssertFalse(change(&detector, .right, held: [.left, .right]))
        XCTAssertFalse(change(&detector, .left, held: [.right]))
        XCTAssertFalse(change(&detector, .right, held: []))
        XCTAssertFalse(change(&detector, .left, held: [.left]))
        XCTAssertTrue(change(&detector, .right, held: [.left, .right]))
    }

    func testModifierActivityBetweenShiftPressesCancelsChord() {
        var detector = BothShiftChordDetector()
        XCTAssertFalse(change(&detector, .right, held: [.right]))
        detector.cancel(shiftIsDown: true) // Command flagsChanged down and up.
        detector.cancel(shiftIsDown: true)
        XCTAssertFalse(change(&detector, .left, held: [.left, .right]))
    }

    func testHeldMouseButtonPreventsCaptureOnEitherPress() {
        for mouseOnFirstPress in [true, false] {
            var detector = BothShiftChordDetector()
            XCTAssertFalse(change(&detector, .left, held: [.left], mouse: mouseOnFirstPress))
            XCTAssertFalse(change(&detector, .right, held: [.left, .right], mouse: !mouseOnFirstPress))
        }
    }

    func testMouseActivityWithMissingModifierFlagsCannotRearmHeldChord() {
        var detector = BothShiftChordDetector()
        XCTAssertFalse(change(&detector, .left, held: [.left]))
        detector.cancel(shiftIsDown: false) // Mouse movement missing Shift flags.
        detector.cancel(shiftIsDown: false) // More pointer movement must not rearm.
        XCTAssertFalse(change(&detector, .right, held: [.left, .right]))
        XCTAssertFalse(change(&detector, .right, held: [.left]))
        XCTAssertFalse(change(&detector, .left, held: []))
        XCTAssertFalse(change(&detector, .right, held: [.right]))
        XCTAssertTrue(change(&detector, .left, held: [.left, .right]))
    }

    func testMouseActivityAfterCaptureCannotAllowRetriggerBeforeRelease() {
        var detector = BothShiftChordDetector()
        XCTAssertFalse(change(&detector, .left, held: [.left]))
        XCTAssertTrue(change(&detector, .right, held: [.left, .right]))
        detector.cancel(shiftIsDown: false)
        XCTAssertFalse(change(&detector, .right, held: [.left]))
        XCTAssertFalse(change(&detector, .right, held: [.left, .right]))
    }

    func testStartingWithShiftHeldRequiresBothReleasedBeforeArming() {
        var detector = BothShiftChordDetector(shiftIsDown: true)
        XCTAssertFalse(change(&detector, .right, held: [.left, .right]))
        XCTAssertFalse(change(&detector, .left, held: [.right]))
        XCTAssertFalse(change(&detector, .right, held: []))
        XCTAssertFalse(change(&detector, .left, held: [.left]))
        XCTAssertTrue(change(&detector, .right, held: [.left, .right]))
    }

    func testAggregateShiftFlagWithoutPhysicalBitsNeverGuessesAChord() {
        var detector = BothShiftChordDetector()
        XCTAssertFalse(detector.shiftChanged(key: .left, flags: .shift))
        XCTAssertFalse(detector.shiftChanged(key: .right, flags: .shift))
        XCTAssertFalse(change(&detector, .right, held: []))
        XCTAssertFalse(change(&detector, .right, held: [.right]))
        XCTAssertTrue(change(&detector, .left, held: [.left, .right]))
    }

    func testMissingFirstPressOrMismatchedPhysicalEventCannotCapture() {
        var detector = BothShiftChordDetector()
        XCTAssertFalse(change(&detector, .right, held: [.left, .right]))
        XCTAssertFalse(change(&detector, .left, held: [.right]))
        XCTAssertFalse(change(&detector, .left, held: [.left, .right]))
        XCTAssertFalse(change(&detector, .left, held: [.right]))
        XCTAssertFalse(change(&detector, .right, held: []))
        XCTAssertFalse(change(&detector, .right, held: [.left]))
        XCTAssertFalse(change(&detector, .right, held: [.left, .right]))
    }

    func testInconsistentAggregateAndPhysicalFlagsCancelTheChord() {
        var detector = BothShiftChordDetector()
        XCTAssertFalse(change(&detector, .left, held: [.left]))
        XCTAssertFalse(detector.shiftChanged(key: .right, flags: NSEvent.ModifierFlags(rawValue: 0x00000006)))
        XCTAssertFalse(change(&detector, .right, held: [.left, .right]))
    }

    func testPersistentCapsLockDoesNotPreventCleanShiftChord() {
        var detector = BothShiftChordDetector()
        XCTAssertFalse(change(&detector, .left, held: [.left], extra: .capsLock))
        XCTAssertTrue(change(&detector, .right, held: [.left, .right], extra: .capsLock))
    }
}
