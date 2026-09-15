// SPDX-License-Identifier: MIT
import AppKit
import Carbon.HIToolbox
import XCTest
@testable import NotchShot

final class GlobalShortcutServiceTests: XCTestCase {
    // These tests register uncommon combinations briefly, never synthesize keyboard
    // input or show a window, and always release registrations before returning.
    private let first = CaptureShortcut(keyCode: UInt16(kVK_F19), modifierFlags: [.control, .option, .command])!
    private let second = CaptureShortcut(keyCode: UInt16(kVK_F20), modifierFlags: [.control, .option, .command])!

    @MainActor
    func testReplacementIsIdempotentAndOnlyCurrentIdentifierCanCapture() throws {
        _ = NSApplication.shared
        let service = GlobalShortcutService()
        defer { service.unregister() }
        try registerOrSkip(first, in: service)
        let oldID = try XCTUnwrap(service.registrationID)
        XCTAssertEqual(service.register(shortcut: first), .success)
        XCTAssertEqual(service.registrationID, oldID, "Repeated setup must not install duplicate handlers.")

        try registerOrSkip(second, in: service)
        let currentID = try XCTUnwrap(service.registrationID)
        XCTAssertNotEqual(oldID, currentID)
        var captures = 0
        service.onCapture = { captures += 1 }
        service.handleHotKey(signature: 0, identifier: currentID)
        service.handleHotKey(signature: GlobalShortcutService.signature, identifier: oldID)
        XCTAssertEqual(captures, 0)
        service.handleHotKey(signature: GlobalShortcutService.signature, identifier: currentID)
        XCTAssertEqual(captures, 1)

        service.unregister()
        service.unregister()
        service.handleHotKey(signature: GlobalShortcutService.signature, identifier: currentID)
        XCTAssertEqual(captures, 1, "Queued callbacks from a removed registration must be ignored.")
        XCTAssertNil(service.registeredShortcut)
        XCTAssertNil(service.registrationID)
    }

    @MainActor
    func testNativeConflictKeepsPreviousRegistrationAndCanRecover() throws {
        _ = NSApplication.shared
        let service = GlobalShortcutService()
        let owner = GlobalShortcutService()
        defer { service.unregister(); owner.unregister() }
        try registerOrSkip(first, in: service)
        try registerOrSkip(second, in: owner)
        let previousID = service.registrationID
        let result = service.register(shortcut: second)
        XCTAssertEqual(result, .failure(OSStatus(eventHotKeyExistsErr)))
        XCTAssertEqual(service.registeredShortcut, first)
        XCTAssertEqual(service.registrationID, previousID)
        XCTAssertNotNil(result.diagnostic)

        var captures = 0
        service.onCapture = { captures += 1 }
        service.handleHotKey(signature: GlobalShortcutService.signature, identifier: try XCTUnwrap(previousID))
        XCTAssertEqual(captures, 1, "A failed replacement must leave the old combination usable.")

        owner.unregister()
        XCTAssertEqual(service.register(shortcut: second), .success)
        XCTAssertEqual(service.registeredShortcut, second)
        XCTAssertNotEqual(service.registrationID, previousID)
        // The successful replacement also freed the old combination.
        XCTAssertEqual(owner.register(shortcut: first), .success)
    }

    @MainActor
    func testStartupConflictLeavesNoRegistrationAndDeinitReleasesOwnership() throws {
        _ = NSApplication.shared
        var owner: GlobalShortcutService? = GlobalShortcutService()
        let contender = GlobalShortcutService()
        defer { owner?.unregister(); contender.unregister() }
        try registerOrSkip(first, in: try XCTUnwrap(owner))
        XCTAssertEqual(contender.register(shortcut: first), .failure(OSStatus(eventHotKeyExistsErr)))
        XCTAssertNil(contender.registeredShortcut)
        XCTAssertNil(contender.registrationID)
        weak var releasedOwner = owner
        owner = nil
        XCTAssertNil(releasedOwner, "Native callback context must not retain the service.")
        XCTAssertEqual(contender.register(shortcut: first), .success)
    }

    @MainActor
    func testRegistrationDiagnosticsPreserveSystemStatus() {
        XCTAssertTrue(GlobalShortcutService.RegistrationResult.success.isSuccess)
        XCTAssertNil(GlobalShortcutService.RegistrationResult.success.diagnostic)
        let conflict = GlobalShortcutService.RegistrationResult.failure(OSStatus(eventHotKeyExistsErr))
        XCTAssertFalse(conflict.isSuccess)
        XCTAssertTrue(conflict.diagnostic?.contains("already in use") == true)
        XCTAssertTrue(GlobalShortcutService.RegistrationResult.failure(-50).diagnostic?.contains("-50") == true)
    }

    @MainActor
    private func registerOrSkip(_ shortcut: CaptureShortcut, in service: GlobalShortcutService) throws {
        let result = service.register(shortcut: shortcut)
        if result == .failure(OSStatus(eventHotKeyExistsErr)) {
            throw XCTSkip("The uncommon test combination \(shortcut.displayString) is already owned by another process.")
        }
        XCTAssertEqual(result, .success)
    }
}
