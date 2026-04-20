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
        XCTAssertTrue(filesTab.waitForExistence(timeout: 3))

        // Should see directory names from the fixture
        let modelsFolder = app.staticTexts["Models"]
        XCTAssertTrue(
            modelsFolder.waitForExistence(timeout: 5),
            "File browser should show Models directory from fixture"
        )
    }

    // MARK: - Class Diagram Generation

    @MainActor
    func testClassDiagramGeneratesPreview() throws {
        // Switch to Preview tab
        let detailTabs = app.groups["detailTabs"]
        if detailTabs.waitForExistence(timeout: 3) {
            let previewTab = detailTabs.buttons["Preview"]
            if previewTab.exists { previewTab.click() }
        }

        // The web view should appear after generation completes
        let webView = app.webViews.firstMatch
        XCTAssertTrue(
            webView.waitForExistence(timeout: 15),
            "Diagram preview web view should appear after class diagram generation"
        )
    }

    @MainActor
    func testMarkupTabShowsContent() throws {
        // Wait for diagram to generate
        let webView = app.webViews.firstMatch
        _ = webView.waitForExistence(timeout: 10)

        // Find and click the Markup tab
        let detailTabs = app.groups["detailTabs"]
        if detailTabs.waitForExistence(timeout: 3) {
            let markupTab = detailTabs.buttons["Markup"]
            if markupTab.waitForExistence(timeout: 3) {
                markupTab.click()
            }
        }

        // The text view should contain diagram markup
        let textView = app.textViews.firstMatch
        XCTAssertTrue(
            textView.waitForExistence(timeout: 5),
            "Markup tab should show a text view with diagram markup"
        )
    }

    // MARK: - Format Switching

    @MainActor
    func testSwitchToNomnomlGeneratesPreview() throws {
        // Wait for initial generation to complete
        let webView = app.webViews.firstMatch
        _ = webView.waitForExistence(timeout: 10)

        // Find the format picker (menu style)
        let formatPicker = app.popUpButtons["Format"]
        guard formatPicker.waitForExistence(timeout: 3) else { return }
        formatPicker.click()

        let nomnomlOption = app.menuItems["Nomnoml"]
        guard nomnomlOption.waitForExistence(timeout: 2) else { return }
        nomnomlOption.click()

        // Wait for regeneration — web view should still exist
        XCTAssertTrue(
            webView.waitForExistence(timeout: 15),
            "Diagram preview should render after switching to Nomnoml format"
        )
    }
}
