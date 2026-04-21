import XCTest

/// Live UI tests that exercise the three SwiftUI `Canvas`-based native
/// diagram renderers by loading the SampleProject fixture, switching the
/// format picker to SVG, and asserting that each canvas's accessibility
/// identifier becomes available.
///
/// These tests complement `DiagramGenerationUITests`, which only verifies
/// the Mermaid/PlantUML/Nomnoml *web* preview paths.
final class NativeCanvasCoverageUITests: XCTestCase {

    private var app: XCUIApplication!

    /// Path to the SampleProject fixture, derived from the source tree at compile time.
    private var fixturePath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()                // SwiftUMLStudioUITests/
            .deletingLastPathComponent()                // SwiftUMLStudio/
            .appendingPathComponent("TestFixtures/SampleProject")
            .path
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-appMode", "Developer",
            "-testFixturePath", fixturePath
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Switch the toolbar Format picker to SVG, routing the preview to the
    /// native `Canvas`-based renderer instead of the web view.
    private func switchFormatToSVG() {
        let formatPicker = app.popUpButtons["formatPicker"]
        XCTAssertTrue(formatPicker.waitForExistence(timeout: 3), "Format picker not found in toolbar")
        formatPicker.click()
        let svgOption = app.menuItems["SVG"]
        XCTAssertTrue(svgOption.waitForExistence(timeout: 2), "SVG menu item not found")
        svgOption.click()
    }

    /// Type an entry point into the given accessibility-identified text field.
    private func typeEntryPoint(_ entryPoint: String, intoField identifier: String) {
        let field = app.textFields[identifier]
        XCTAssertTrue(field.waitForExistence(timeout: 3), "Entry point field \(identifier) not found")
        field.click()
        field.typeText(entryPoint)
    }

    // MARK: - Class diagram native canvas

    /// Switching Format → SVG on the default Class Diagram mode should mount
    /// `NativeDiagramView`, exercising its `Canvas` draw closures.
    @MainActor
    func testClassDiagramNativeCanvasRenders() throws {
        // Let the fixture loader + initial generation settle.
        sleep(2)
        switchFormatToSVG()

        let canvas = app.descendants(matching: .any)
            .matching(identifier: "nativeDiagramCanvas").firstMatch
        XCTAssertTrue(
            canvas.waitForExistence(timeout: 15),
            "Class diagram native canvas should render when format is SVG"
        )
    }

    // MARK: - Sequence diagram native canvas

    /// Switching to Sequence Diagram with a valid entry point and SVG format
    /// should mount `NativeSequenceDiagramView`.
    @MainActor
    func testSequenceDiagramNativeCanvasRenders() throws {
        sleep(2)

        let modePicker = app.outlines["modePicker"]
        XCTAssertTrue(modePicker.waitForExistence(timeout: 3))
        modePicker.staticTexts["Sequence Diagram"].click()

        typeEntryPoint("AuthService.login", intoField: "entryPointField")
        switchFormatToSVG()

        let canvas = app.descendants(matching: .any)
            .matching(identifier: "nativeSequenceCanvas").firstMatch
        XCTAssertTrue(
            canvas.waitForExistence(timeout: 15),
            "Sequence diagram native canvas should render when format is SVG"
        )
    }

    // MARK: - Activity diagram native canvas

    /// Switching to Activity Diagram with a valid entry point and SVG format
    /// should mount `NativeActivityDiagramView`.
    @MainActor
    func testActivityDiagramNativeCanvasRenders() throws {
        sleep(2)

        let modePicker = app.outlines["modePicker"]
        XCTAssertTrue(modePicker.waitForExistence(timeout: 3))
        modePicker.staticTexts["Activity Diagram"].click()

        typeEntryPoint("AuthService.login", intoField: "activityEntryPointField")
        switchFormatToSVG()

        let canvas = app.descendants(matching: .any)
            .matching(identifier: "nativeActivityCanvas").firstMatch
        XCTAssertTrue(
            canvas.waitForExistence(timeout: 15),
            "Activity diagram native canvas should render when format is SVG"
        )
    }
}
