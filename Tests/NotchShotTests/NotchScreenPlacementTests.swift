// SPDX-License-Identifier: MIT
import AppKit
import XCTest
@testable import NotchShot

final class NotchScreenPlacementTests: XCTestCase {
    @MainActor
    func testCollapsedPanelFollowsWithAutoCollapseDisabledAndUpdatesLandingAnchor() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let host = try XCTUnwrap(fixture.window.contentView)
        XCTAssertFalse(fixture.store.autoCollapseEnabled)
        XCTAssertFalse(fixture.store.isExpanded)
        XCTAssertEqual(fixture.controller.activeDisplayID, 1)
        assertAnchored(fixture.window.frame, to: fixture.inputs.screens[0].notchRect)

        movePointerToSecondDisplay(fixture)

        XCTAssertEqual(fixture.controller.activeDisplayID, 2)
        XCTAssertEqual(fixture.store.notchWidth, 190)
        XCTAssertEqual(fixture.store.notchHeight, 28)
        XCTAssertEqual(fixture.window.frame.width, 226, accuracy: 0.5)
        XCTAssertEqual(fixture.window.frame.height, 32, accuracy: 0.5,
                       "The compact surface keeps its minimum height on an external display.")
        assertAnchored(fixture.window.frame, to: fixture.inputs.screens[1].notchRect)
        let landing = try XCTUnwrap(fixture.controller.compactLandingFrame)
        assertAnchored(landing, to: fixture.inputs.screens[1].notchRect)
        XCTAssertEqual(landing.width, 28, accuracy: 0.5)
        XCTAssertEqual(landing.height, 18, accuracy: 0.5)
        assertSameHiddenSurface(fixture, host: host)
    }

    @MainActor
    func testMovingExpandedSettingsPreservesWindowHostAndShelfState() throws {
        let shot = makeCapture()
        let fixture = try makeFixture { store in
            store.captures = [shot]
            store.selectedID = shot.id
            store.page = .settings
            store.isExpanded = true
        }
        defer { fixture.close() }
        let host = try XCTUnwrap(fixture.window.contentView)
        let initialSize = fixture.window.frame.size

        movePointerToSecondDisplay(fixture)

        XCTAssertEqual(fixture.controller.activeDisplayID, 2)
        XCTAssertTrue(fixture.store.isExpanded)
        XCTAssertEqual(fixture.store.page, .settings)
        XCTAssertEqual(fixture.store.selectedID, shot.id)
        XCTAssertEqual(fixture.store.captures.map(\.id), [shot.id])
        XCTAssertEqual(fixture.store.captures.first?.accessibilityText, "Existing shelf content")
        XCTAssertEqual(fixture.window.frame.width, initialSize.width, accuracy: 0.5)
        XCTAssertEqual(fixture.window.frame.height, initialSize.height, accuracy: 0.5)
        XCTAssertEqual(fixture.controller.presentation.progress, 1)
        assertAnchored(fixture.window.frame, to: fixture.inputs.screens[1].notchRect)
        assertSameHiddenSurface(fixture, host: host)
    }

    @MainActor
    func testDisablingFollowReturnsHomeWithoutDwellWhenPointerIsOutsidePanel() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        movePointerToSecondDisplay(fixture)
        fixture.store.followActiveScreen = false
        fixture.controller.refreshScreenPlacement()

        XCTAssertEqual(fixture.controller.activeDisplayID, 1)
        assertAnchored(fixture.window.frame, to: fixture.inputs.screens[0].notchRect)
        fixture.inputs.time += 1
        fixture.controller.refreshScreenPlacement()
        XCTAssertEqual(fixture.controller.activeDisplayID, 1,
                       "Following stays off even though the pointer is still on the other display.")
        XCTAssertFalse(fixture.window.isVisible)
    }

    @MainActor
    func testBusyCaptureRequiresFreshDwellAfterRelease() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        fixture.store.isCapturing = true
        fixture.inputs.pointer = fixture.inputs.secondDisplayPointer
        fixture.controller.refreshScreenPlacement()
        fixture.inputs.time += 1
        fixture.controller.refreshScreenPlacement()
        XCTAssertEqual(fixture.controller.activeDisplayID, 1)

        fixture.store.isCapturing = false
        fixture.controller.refreshScreenPlacement()
        XCTAssertEqual(fixture.controller.activeDisplayID, 1)
        fixture.inputs.time += 0.2
        fixture.controller.refreshScreenPlacement()
        XCTAssertEqual(fixture.controller.activeDisplayID, 1)
        fixture.inputs.time += 0.2
        fixture.controller.refreshScreenPlacement()
        XCTAssertEqual(fixture.controller.activeDisplayID, 2)
        XCTAssertFalse(fixture.window.isVisible)
    }

    @MainActor
    func testPressedMouseButtonDefersMoveUntilFreshDwellAfterRelease() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        fixture.inputs.buttons = 1
        fixture.inputs.pointer = fixture.inputs.secondDisplayPointer
        fixture.controller.refreshScreenPlacement()
        fixture.inputs.time += 1
        fixture.controller.refreshScreenPlacement()
        XCTAssertEqual(fixture.controller.activeDisplayID, 1)

        fixture.inputs.buttons = 0
        fixture.controller.refreshScreenPlacement()
        XCTAssertEqual(fixture.controller.activeDisplayID, 1)
        fixture.inputs.time += 0.4
        fixture.controller.refreshScreenPlacement()
        XCTAssertEqual(fixture.controller.activeDisplayID, 2)
        XCTAssertFalse(fixture.window.isVisible)
    }

    @MainActor
    func testUnpluggedCurrentDisplayReturnsToValidHomeEvenDuringCapture() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let host = try XCTUnwrap(fixture.window.contentView)
        movePointerToSecondDisplay(fixture)
        fixture.store.isCapturing = true
        fixture.inputs.buttons = 1
        fixture.inputs.screens.removeAll { $0.id == 2 }

        fixture.controller.refreshScreenPlacement()

        XCTAssertEqual(fixture.controller.activeDisplayID, 1)
        XCTAssertTrue(fixture.store.isCapturing)
        XCTAssertEqual(fixture.store.notchHeight, 32)
        assertAnchored(fixture.window.frame, to: fixture.inputs.screens[0].notchRect)
        assertSameHiddenSurface(fixture, host: host)
    }

    @MainActor
    func testTopologyChangeConsumedByPageObservationResetsCollapsedSizeMinimum() async throws {
        let fixture = try makeFixture(firstNotchHeight: 48)
        defer { fixture.close() }
        let host = try XCTUnwrap(fixture.window.contentView)
        XCTAssertEqual(fixture.window.frame.height, 48, accuracy: 0.5)
        XCTAssertFalse(fixture.store.isExpanded)

        fixture.inputs.screens.removeAll { $0.id == 1 }
        fixture.inputs.preferredID = 2
        fixture.inputs.pointer = fixture.inputs.secondDisplayPointer
        // Let presentation observation see the new topology before a screen
        // refresh. Reusing the old size spring would clamp this display's
        // compact height to the removed display's 48-point minimum.
        fixture.store.page = .settings
        try await waitForObservation { fixture.controller.activeDisplayID == 2 }

        XCTAssertFalse(fixture.controller.isAnimating)
        XCTAssertFalse(fixture.store.isExpanded)
        XCTAssertEqual(fixture.store.page, .settings)
        XCTAssertEqual(fixture.store.notchHeight, 28)
        XCTAssertEqual(fixture.controller.presentation.progress, 0)
        XCTAssertEqual(fixture.controller.presentation.size.height, 32, accuracy: 0.5)
        XCTAssertEqual(fixture.window.frame.height, 32, accuracy: 0.5)
        assertAnchored(fixture.window.frame, to: fixture.inputs.screens[0].notchRect)
        assertSameHiddenSurface(fixture, host: host)
    }

    @MainActor
    private func makeFixture(firstNotchHeight: CGFloat = 32,
                             configure: (CaptureStore) -> Void = { _ in }) throws -> Fixture {
        _ = NSApplication.shared
        guard NotchGeometry.preferredScreen != nil else {
            throw XCTSkip("This native integration test requires WindowServer display access; the test process is headless or sandboxed.")
        }
        let previousWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        let (preferences, clipboard) = isolatedStoreDependencies()
        preferences.set(true, forKey: "followActiveScreen")
        preferences.set(false, forKey: "autoCollapseEnabled")
        let store = CaptureStore(preferences: preferences, clipboard: clipboard)
        configure(store)
        let inputs = DisplayInputs(firstNotchHeight: firstNotchHeight)
        let controller = NotchPanelController(store: store,
                                              displays: { inputs.screens },
                                              preferredDisplayID: { inputs.preferredID },
                                              mouseLocation: { inputs.pointer },
                                              pressedMouseButtons: { inputs.buttons },
                                              clock: { inputs.time })
        let window = try XCTUnwrap(NSApp.windows.first {
            !previousWindows.contains(ObjectIdentifier($0)) && $0.title == "NotchShot"
        })
        XCTAssertFalse(window.isVisible, "The regression test must not present UI.")
        return Fixture(store: store, controller: controller, window: window,
                       inputs: inputs, previousWindows: previousWindows)
    }

    @MainActor
    private func movePointerToSecondDisplay(_ fixture: Fixture) {
        fixture.inputs.pointer = fixture.inputs.secondDisplayPointer
        fixture.controller.refreshScreenPlacement()
        XCTAssertEqual(fixture.controller.activeDisplayID, 1, "A new pointer display requires dwell.")
        fixture.inputs.time += 0.4
        fixture.controller.refreshScreenPlacement()
        XCTAssertEqual(fixture.controller.activeDisplayID, 2)
    }

    @MainActor
    private func waitForObservation(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw NSError(domain: "NotchScreenPlacementTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "The store change did not update native screen placement within one second."])
    }

    @MainActor
    private func assertSameHiddenSurface(_ fixture: Fixture, host: NSView,
                                         file: StaticString = #filePath, line: UInt = #line) {
        let createdPanels = NSApp.windows.filter {
            !fixture.previousWindows.contains(ObjectIdentifier($0)) && $0.title == "NotchShot"
        }
        XCTAssertEqual(createdPanels.count, 1, file: file, line: line)
        XCTAssertTrue(createdPanels.first === fixture.window, file: file, line: line)
        XCTAssertTrue(fixture.window.contentView === host, file: file, line: line)
        let dropHost = host as? ShotDropHostingView<NotchRootView>
        XCTAssertTrue(dropHost?.captureStore === fixture.store, file: file, line: line)
        XCTAssertFalse(fixture.window.isVisible, file: file, line: line)
    }

    private func assertAnchored(_ frame: CGRect, to notch: CGRect,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(frame.midX, notch.midX, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(frame.maxY, notch.maxY, accuracy: 0.5, file: file, line: line)
    }

    private func makeCapture() -> CaptureResult {
        CaptureResult(appName: "Display test", bundleIdentifier: "com.example.display-test",
                      windowTitle: "Existing shot", axTree: [],
                      accessibilityText: "Existing shelf content", ocrText: "")
    }
}

@MainActor
private final class DisplayInputs {
    var screens: [NotchDisplay]
    var preferredID: CGDirectDisplayID? = 1
    var pointer = CGPoint(x: 400, y: 400)
    var buttons = 0
    var time: TimeInterval = 100
    let secondDisplayPointer = CGPoint(x: -1000, y: 500)

    init(firstNotchHeight: CGFloat = 32) {
        screens = [
            NotchDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                         notchRect: CGRect(x: 625, y: 900 - firstNotchHeight, width: 190, height: firstNotchHeight)),
            NotchDisplay(id: 2, frame: CGRect(x: -1920, y: 80, width: 1920, height: 1080),
                         notchRect: CGRect(x: -1055, y: 1132, width: 190, height: 28))
        ]
    }
}

@MainActor
private struct Fixture {
    let store: CaptureStore
    let controller: NotchPanelController
    let window: NSWindow
    let inputs: DisplayInputs
    let previousWindows: Set<ObjectIdentifier>

    func close() {
        store.stop()
        window.close()
    }
}
