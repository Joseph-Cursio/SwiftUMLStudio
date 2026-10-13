import XCTest

/// UI tests that load the SampleProject fixture and verify diagram generation end-to-end.
final class DiagramGenerationUITests: XCTestCase {

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
        app.launchArguments += UITestLaunchArguments.plantUMLConsentUndecided
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Fixture Loading

    @MainActor
    func testFixtureLoadsPathSummary() throws {
        // The toolbar should show "SampleProject" instead of "No source selected"
        let noSource = app.staticTexts["No source selected"]
        // Wait a moment for the fixture to load
        sleep(2)
        XCTAssertFalse(
            noSource.exists,
            "Path summary should not show 'No source selected' when fixture is loaded"
        )
    }

    @MainActor
    func testFixturePopulatesFileBrowser() throws {
        // Wait for the Files tab to exist (sidebar segmented control)
        let filesTab = app.radioButtons["Files"]
        XCTAssertTrue(filesTab.waitForExistence(timeout: UITestTimeout.element))

        // Should see directory names from the fixture
        let modelsFolder = app.staticTexts["Models"]
        XCTAssertTrue(
            modelsFolder.waitForExistence(timeout: UITestTimeout.element),
            "File browser should show Models directory from fixture"
        )
    }

    // MARK: - Class Diagram Generation

    /// The direct build's default format is PlantUML, which renders on planttext.com, so the
    /// generated preview is the consent card until the user allows it. It is never a web view:
    /// that would mean the diagram had been uploaded unasked.
    @MainActor
    func testClassDiagramPreviewAsksBeforeUploading() throws {
        // Switch to Preview tab
        let detailTabs = app.tabGroups["detailTabs"]
        XCTAssertTrue(
            detailTabs.waitForExistence(timeout: UITestTimeout.element),
            "Detail tabs should exist in Developer mode"
        )
        detailTabs.tabs["Preview"].click()

        XCTAssertTrue(
            app.buttons["plantUMLConsentAllowButton"].waitForExistence(timeout: UITestTimeout.element),
            "The PlantUML preview should ask for consent after class diagram generation"
        )
        XCTAssertTrue(
            app.buttons["plantUMLConsentUseMermaidButton"].exists,
            "With a source to regenerate from, the card should offer Mermaid"
        )
        XCTAssertFalse(app.webViews.firstMatch.exists, "Nothing should load before consent")
    }

    @MainActor
    func testMarkupTabShowsContent() throws {
        // Wait for diagram to generate
        XCTAssertTrue(
            app.buttons["plantUMLConsentAllowButton"].waitForExistence(timeout: UITestTimeout.element),
            "The PlantUML preview should be generated"
        )

        // Find and click the Markup tab
        let detailTabs = app.tabGroups["detailTabs"]
        XCTAssertTrue(
            detailTabs.waitForExistence(timeout: UITestTimeout.element),
            "Detail tabs should exist in Developer mode"
        )
        let markupTab = detailTabs.tabs["Markup"]
        XCTAssertTrue(
            markupTab.waitForExistence(timeout: UITestTimeout.element),
            "Markup tab should exist"
        )
        markupTab.click()

        // The text view should contain diagram markup
        let textView = app.textViews.firstMatch
        XCTAssertTrue(
            textView.waitForExistence(timeout: UITestTimeout.element),
            "Markup tab should show a text view with diagram markup"
        )
    }

    // MARK: - Format Switching

    @MainActor
    func testSwitchToNomnomlGeneratesPreview() throws {
        // Wait for initial generation to complete
        XCTAssertTrue(
            app.buttons["plantUMLConsentAllowButton"].waitForExistence(timeout: UITestTimeout.element),
            "The PlantUML preview should be generated"
        )
        let webView = app.webViews.firstMatch

        // Find the format picker (menu style)
        let formatPicker = app.popUpButtons["formatPicker"]
        XCTAssertTrue(
            formatPicker.waitForExistence(timeout: UITestTimeout.element),
            "Format picker should exist in Developer mode"
        )
        formatPicker.click()

        let nomnomlOption = app.menuItems["Nomnoml"]
        XCTAssertTrue(
            nomnomlOption.waitForExistence(timeout: UITestTimeout.element),
            "Nomnoml should be offered in the format menu"
        )
        nomnomlOption.click()

        // Wait for regeneration — web view should still exist
        XCTAssertTrue(
            webView.waitForExistence(timeout: UITestTimeout.element),
            "Diagram preview should render after switching to Nomnoml format"
        )
    }
}
