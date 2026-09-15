// SPDX-License-Identifier: MIT
import AppKit
import Carbon.HIToolbox
import XCTest
@testable import NotchShot

final class HoverCopyShortcutTests: XCTestCase {
    @MainActor
    func testBindsOnlyCommandCWhileOneValidThumbnailIsHovered() {
        let binding = TestBinding()
        let service = HoverCopyShortcutService(binding: binding)
        XCTAssertNil(binding.registeredShortcut)
        let owner = UUID(), shot = UUID()
        var copied = [UUID]()

        XCTAssertTrue(service.begin(owner: owner, captureID: shot, isValid: { true }, copy: {
            copied.append(shot)
            return true
        }))
        XCTAssertEqual(binding.registeredShortcut?.keyCode, UInt16(kVK_ANSI_C))
        XCTAssertEqual(binding.registeredShortcut?.modifierFlags, [.command])
        binding.onCapture?()
        binding.onCapture?()
        XCTAssertEqual(copied, [shot, shot])

        service.stop(owner: owner)
        XCTAssertNil(binding.registeredShortcut)
        XCTAssertNil(binding.onCapture)
        XCTAssertFalse(service.isRegistered)
        XCTAssertNil(service.captureID)
    }

    @MainActor
    func testRetargetRejectsAnOldQueuedCopyAndAnOldThumbnailExit() throws {
        let binding = TestBinding()
        let service = HoverCopyShortcutService(binding: binding)
        let firstOwner = UUID(), secondOwner = UUID()
        let first = UUID(), second = UUID()
        var copied = [UUID]()
        service.begin(owner: firstOwner, captureID: first, isValid: { true }, copy: {
            copied.append(first)
            return true
        })
        let queuedFirstCopy = try XCTUnwrap(binding.onCapture)

        service.begin(owner: secondOwner, captureID: second, isValid: { true }, copy: {
            copied.append(second)
            return true
        })
        service.stop(owner: firstOwner)
        queuedFirstCopy()
        XCTAssertTrue(copied.isEmpty)
        XCTAssertTrue(service.isRegistered)
        XCTAssertEqual(service.captureID, second)
        binding.onCapture?()
        XCTAssertEqual(copied, [second])
        XCTAssertEqual(binding.registrations, 2, "Each new target needs a fresh native registration.")
        service.stop()
    }

    @MainActor
    func testInvalidPointerOrNavigationAtDeliveryReleasesCopyWithoutWriting() throws {
        let binding = TestBinding()
        let service = HoverCopyShortcutService(binding: binding)
        var valid = true
        var copies = 0
        service.begin(owner: UUID(), captureID: UUID(), isValid: { valid }, copy: {
            copies += 1
            return true
        })
        let queuedCopy = try XCTUnwrap(binding.onCapture)
        valid = false
        queuedCopy()
        XCTAssertEqual(copies, 0)
        XCTAssertNil(binding.registeredShortcut)
        XCTAssertFalse(service.isRegistered)
        valid = true
        queuedCopy()
        XCTAssertEqual(copies, 0, "Returning to the old location must not revive its old registration.")
    }

    @MainActor
    func testDeletedShotFailureReleasesCopy() {
        let binding = TestBinding()
        let service = HoverCopyShortcutService(binding: binding)
        var attemptedCopies = 0
        service.begin(owner: UUID(), captureID: UUID(), isValid: { true }, copy: {
            attemptedCopies += 1
            return false
        })
        binding.onCapture?()
        XCTAssertEqual(attemptedCopies, 1)
        XCTAssertNil(binding.registeredShortcut)
        XCTAssertNil(binding.onCapture)
        XCTAssertFalse(service.isRegistered)
    }

    @MainActor
    func testDisabledScopeNeverRegistersAndStopRejectsDeferredDelivery() throws {
        let binding = TestBinding()
        let service = HoverCopyShortcutService(binding: binding)
        var copies = 0
        XCTAssertFalse(service.begin(owner: UUID(), captureID: UUID(), isValid: { false }, copy: {
            copies += 1
            return true
        }))
        XCTAssertEqual(binding.registrations, 0)
        XCTAssertNil(binding.onCapture)

        service.begin(owner: UUID(), captureID: UUID(), isValid: { true }, copy: {
            copies += 1
            return true
        })
        let queuedCopy = try XCTUnwrap(binding.onCapture)
        service.stop()
        service.stop()
        queuedCopy()
        XCTAssertEqual(copies, 0)
        XCTAssertNil(binding.registeredShortcut)
    }

    @MainActor
    func testRegistrationFailureDoesNotLeaveAnActiveCopyScopeAndCanRecover() {
        let binding = TestBinding()
        let service = HoverCopyShortcutService(binding: binding)
        var copies = 0
        binding.result = .failure(OSStatus(eventHotKeyExistsErr))
        XCTAssertFalse(service.begin(owner: UUID(), captureID: UUID(), isValid: { true }, copy: {
            copies += 1
            return true
        }))
        XCTAssertFalse(service.isRegistered)
        XCTAssertNil(service.owner)
        XCTAssertNil(binding.onCapture)
        XCTAssertNil(binding.registeredShortcut)
        XCTAssertEqual(copies, 0)

        binding.result = .success
        XCTAssertTrue(service.begin(owner: UUID(), captureID: UUID(), isValid: { true }, copy: {
            copies += 1
            return true
        }))
        binding.onCapture?()
        XCTAssertEqual(copies, 1)
        service.stop()
    }
}

@MainActor
private final class TestBinding: HoverCopyShortcutBinding {
    var onCapture: (() -> Void)?
    var result = GlobalShortcutService.RegistrationResult.success
    var registeredShortcut: CaptureShortcut?
    var registrations = 0

    func register(shortcut: CaptureShortcut) -> GlobalShortcutService.RegistrationResult {
        registrations += 1
        if result.isSuccess { registeredShortcut = shortcut }
        return result
    }

    func unregister() { registeredShortcut = nil }
}
