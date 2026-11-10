import XCTest

/// Live UI tests that exercise the three SwiftUI `Canvas`-based native
/// diagram renderers by loading the SampleProject fixture, switching the
/// format picker to SVG, and asserting that each canvas's accessibility
/// identifier becomes available.
///
/// These tests complement `DiagramGenerationUITests`, which only verifies
/// the Mermaid/PlantUML/Nomnoml *web* preview paths.
final class NativeCanvasCoverageUITests: XCTestCase {

    /// Path to the SampleProject fixture, derived from the source tree at compile time.
    private var fixturePath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()                // SwiftUMLStudioUITests/
            .deletingLastPathComponent()                // SwiftUMLStudio/
            .appendingPathComponent("TestFixtures/SampleProject")
            .path
    }

    /// The app, launched as every test here needs it. Each test holds its own, so nothing is
    /// stored between tests and none needs unwrapping.
    @MainActor
    private func launchApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-appMode", "Developer",
            "-testFixturePath", fixturePath
        ]
        app.launchArguments += UITestLaunchArguments.plantUMLConsentUndecided
        app.launch()
        return app
    }

    // MARK: - Helpers

    /// Switch the toolbar Format picker to SVG, routing the preview to the
    /// native `Canvas`-based renderer instead of the web view.
    @MainActor
    private func switchFormatToSVG(in app: XCUIApplication) {
        let formatPicker = app.popUpButtons["formatPicker"]
        XCTAssertTrue(
            formatPicker.waitForExistence(timeout: UITestTimeout.element),
            "Format picker not found in toolbar"
        )
        formatPicker.click()
        let svgOption = app.menuItems["SVG"]
        XCTAssertTrue(svgOption.waitForExistence(timeout: UITestTimeout.element), "SVG menu item not found")
        svgOption.click()
    }

    /// Type an entry point into the given accessibility-identified text field.
    @MainActor
    private func typeEntryPoint(_ entryPoint: String, intoField identifier: String, in app: XCUIApplication) {
        let field = app.textFields[identifier]
        XCTAssertTrue(
            field.waitForExistence(timeout: UITestTimeout.element),
            "Entry point field \(identifier) not found"
        )
        field.click()
        field.typeText(entryPoint)
    }

    // MARK: - Class diagram native canvas

    /// Switching Format → SVG on the default Class Diagram mode should mount
    /// `NativeDiagramView`, exercising its `Canvas` draw closures.
    @MainActor
    func testClassDiagramNativeCanvasRenders() throws {
        let app = launchApp()
        // Let the fixture loader + initial generation settle.
        sleep(2)
        switchFormatToSVG(in: app)

        let canvas = app.descendants(matching: .any)
            .matching(identifier: "nativeDiagramCanvas").firstMatch
        XCTAssertTrue(
            canvas.waitForExistence(timeout: UITestTimeout.element),
            "Class diagram native canvas should render when format is SVG"
        )
    }

    // MARK: - Sequence diagram native canvas

    /// Switching to Sequence Diagram with a valid entry point and SVG format
    /// should mount `NativeSequenceDiagramView`.
    @MainActor
    func testSequenceDiagramNativeCanvasRenders() throws {
        let app = launchApp()
        sleep(2)

        let modePicker = app.outlines["modePicker"]
        XCTAssertTrue(modePicker.waitForExistence(timeout: UITestTimeout.element))
        modePicker.staticTexts["Sequence Diagram"].click()

        typeEntryPoint("AuthService.login", intoField: "entryPointField", in: app)
        switchFormatToSVG(in: app)

        let canvas = app.descendants(matching: .any)
            .matching(identifier: "nativeSequenceCanvas").firstMatch
        XCTAssertTrue(
            canvas.waitForExistence(timeout: UITestTimeout.element),
            "Sequence diagram native canvas should render when format is SVG"
        )
    }

    // MARK: - Activity diagram native canvas

    /// Switching to Activity Diagram with a valid entry point and SVG format
    /// should mount `NativeActivityDiagramView`.
    @MainActor
    func testActivityDiagramNativeCanvasRenders() throws {
        let app = launchApp()
        sleep(2)

        let modePicker = app.outlines["modePicker"]
        XCTAssertTrue(modePicker.waitForExistence(timeout: UITestTimeout.element))
        modePicker.staticTexts["Activity Diagram"].click()

        typeEntryPoint("AuthService.login", intoField: "activityEntryPointField", in: app)
        switchFormatToSVG(in: app)

        let canvas = app.descendants(matching: .any)
            .matching(identifier: "nativeActivityCanvas").firstMatch
        XCTAssertTrue(
            canvas.waitForExistence(timeout: UITestTimeout.element),
            "Activity diagram native canvas should render when format is SVG"
        )
    }
}
