import XCTest

// Drives the ACTUAL InfiniCanvasHost app through Apple's UI test service.
// Unlike an HTML mock or a CALayer snapshot, XCTAttachment(screenshot:)
// records composited, running iPadOS UI pixels and its native Liquid Glass.
final class InfiniCanvasNativeVisualTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func capture(_ app: XCUIApplication, label: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = label
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testRealNativeMorphStages() throws {
        for progress in [0, 25, 60, 100] {
            let app = XCUIApplication()
            app.launchArguments = ["--infini-visual-morph=\(progress)"]
            app.launch()
            XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20),
                          "The actual native app must have a visible iPad window")
            Thread.sleep(forTimeInterval: 1.7)
            capture(app, label: "Real-InfiniCanvas-morph-\(progress)-percent")
            app.terminate()
        }
    }

    func testActualEditableInkPixelsAtBothZoomLevels() throws {
        for config in ["127:0.102", "127:1.0"] {
            let app = XCUIApplication()
            app.launchArguments = ["--infini-visual-ink=\(config)"]
            app.launch()
            XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
            Thread.sleep(forTimeInterval: 3.0)
            capture(app, label: "Real-InfiniCanvas-editable-PencilKit-\(config)")
            app.terminate()
        }
    }

    func testSizeTriggerReallyAcceptsUpwardGesture() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        let control = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", "On-screen size")).firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 20),
                      "Original size trigger must remain in existing toolbar")
        let oldLabel = control.label
        let start = control.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: -135))
        start.press(forDuration: 0.08, thenDragTo: end)
        Thread.sleep(forTimeInterval: 0.6)
        capture(app, label: "Real-InfiniCanvas-after-user-like-width-swipe")
        XCTAssertNotEqual(control.label, oldLabel,
                          "Upward drag on original size pill must change selected point width")
        app.terminate()
    }
}
