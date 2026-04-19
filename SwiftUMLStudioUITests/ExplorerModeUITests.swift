import XCTest

final class ExplorerModeUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-appMode", "Explorer"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testExplorerModeShowsOpenButton() throws {
        XCTAssertTrue(
            app.buttons["Open…"].waitForExistence(timeout: 3),
            "Open button should exist in Explorer mode"
        )
    }

    @MainActor
    func testExplorerModeShowsSaveToHistory() throws {
        XCTAssertTrue(
            app.buttons["Save to History"].waitForExistence(timeout: 3),
            "Save to History button should exist in Explorer mode"
        )
    }

    @MainActor
    func testExplorerModeHidesDeveloperControls() throws {
        // Mode picker should not exist in Explorer mode
        XCTAssertFalse(
            app.radioGroups["modePicker"].exists,
            "Mode picker should be hidden in Explorer mode"
        )
    }

    @MainActor
    func testExplorerModeShowsAppModeToggle() throws {
        let toggle = app.radioGroups["appModePicker"]
            .exists ? app.radioGroups["appModePicker"] : app.segmentedControls["appModePicker"]
        // The mode toggle should be accessible somewhere
        XCTAssertTrue(
            app.staticTexts["Explorer"].waitForExistence(timeout: 3)
            || toggle.exists,
            "App mode toggle should be visible in Explorer mode"
        )
    }
}
