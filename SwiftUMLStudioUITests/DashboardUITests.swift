import XCTest

final class DashboardUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-appMode", "Developer"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Sidebar

    @MainActor
    func testFileBrowserSectionExists() throws {
        XCTAssertTrue(
            app.staticTexts["Files"].waitForExistence(timeout: 3),
            "Files section header should exist in sidebar"
        )
    }

    @MainActor
    func testHistorySectionExists() throws {
        XCTAssertTrue(
            app.staticTexts["History"].waitForExistence(timeout: 3),
            "History section header should exist in sidebar"
        )
    }

    // MARK: - Toolbar state

    @MainActor
    func testSaveButtonDisabledWithoutDiagram() throws {
        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3), "Save button not found")
        XCTAssertFalse(saveButton.isEnabled, "Save should be disabled when no diagram is generated")
    }

    @MainActor
    func testOpenButtonExists() throws {
        let openButton = app.buttons["Open…"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 3), "Open button not found")
        XCTAssertTrue(openButton.isEnabled, "Open button should be enabled")
    }

    @MainActor
    func testFormatPickerDefaultsToPlantUML() throws {
        let formatPicker = app.radioGroups["Format"]
        guard formatPicker.waitForExistence(timeout: 3) else { return }
        XCTAssertTrue(
            formatPicker.radioButtons["PlantUML"].isSelected,
            "PlantUML should be selected by default"
        )
    }

    @MainActor
    func testDepthStepperAppearsInSequenceMode() throws {
        let modePicker = app.radioGroups["modePicker"]
        XCTAssertTrue(modePicker.waitForExistence(timeout: 3))
        modePicker.radioButtons["Sequence Diagram"].click()

        let stepper = app.steppers["depthStepper"]
        XCTAssertTrue(
            stepper.waitForExistence(timeout: 2),
            "Depth stepper should appear in Sequence Diagram mode"
        )
    }

    @MainActor
    func testNoSourceSelectedLabelOnLaunch() throws {
        XCTAssertTrue(
            app.staticTexts["No source selected"].waitForExistence(timeout: 3),
            "Path summary should show 'No source selected' on launch"
        )
    }

    @MainActor
    func testModePickerExists() throws {
        let modePicker = app.radioGroups["modePicker"]
        XCTAssertTrue(modePicker.waitForExistence(timeout: 3), "Mode picker should exist")
        XCTAssertTrue(
            modePicker.radioButtons.count >= 3,
            "Mode picker should have at least 3 options"
        )
    }
}
