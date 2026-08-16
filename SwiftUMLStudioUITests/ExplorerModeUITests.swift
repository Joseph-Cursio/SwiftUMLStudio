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
            app.buttons["Open…"].waitForExistence(timeout: UITestTimeout.element),
            "Open button should exist in Explorer mode"
        )
    }

    @MainActor
    func testExplorerModeShowsSaveToHistory() throws {
        XCTAssertTrue(
            app.buttons["Save to History"].waitForExistence(timeout: UITestTimeout.element),
            "Save to History button should exist in Explorer mode"
        )
    }

    @MainActor
    func testExplorerModeHidesDeveloperControls() throws {
        // Mode picker should not exist in Explorer mode
        XCTAssertFalse(
            app.outlines["modePicker"].exists,
            "Mode picker should be hidden in Explorer mode"
        )
    }

    @MainActor
    func testExplorerModeShowsAppModeToggle() throws {
        // The picker is a RadioGroup whose options are RadioButtons. The old
        // version waited on `staticTexts["Explorer"]`, which never matches, and
        // passed only via an `||` fallback after burning the whole timeout.
        let picker = app.radioGroups["appModePicker"]
        XCTAssertTrue(
            picker.waitForExistence(timeout: UITestTimeout.element),
            "App mode picker should be visible in Explorer mode"
        )
        // SwiftUI reports radio-button selection through AXValue (1 = selected)
        // and does not set AXSelected, so `isSelected` is false even for the
        // active option. Assert on the value instead.
        let selection = (picker.radioButtons["Explorer"].value as? NSNumber)?.intValue
        XCTAssertEqual(
            selection, 1,
            "Explorer should be the selected mode when launched with -appMode Explorer"
        )
    }
}
