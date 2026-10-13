import XCTest

final class DashboardUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-appMode", "Developer"]
        app.launchArguments += UITestLaunchArguments.plantUMLConsentUndecided
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Sidebar

    @MainActor
    func testFileBrowserSectionExists() throws {
        XCTAssertTrue(
            app.radioButtons["Files"].waitForExistence(timeout: UITestTimeout.element),
            "Files tab should exist in sidebar"
        )
    }

    @MainActor
    func testHistorySectionExists() throws {
        XCTAssertTrue(
            app.radioButtons["History"].waitForExistence(timeout: UITestTimeout.element),
            "History tab should exist in sidebar"
        )
    }

    // MARK: - Toolbar state

    @MainActor
    func testSaveButtonDisabledWithoutDiagram() throws {
        // SwiftUI on macOS 26 reports the accessibilityIdentifier on both
        // the toolbar wrapper and the inner button, so a label-based query
        // matches multiple elements. .firstMatch picks one deterministically.
        let saveButton = app.buttons["toolbarSaveButton"].firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: UITestTimeout.element), "Save button not found")
        XCTAssertFalse(saveButton.isEnabled, "Save should be disabled when no diagram is generated")
    }

    @MainActor
    func testOpenButtonExists() throws {
        let openButton = app.buttons["toolbarOpenButton"].firstMatch
        XCTAssertTrue(openButton.waitForExistence(timeout: UITestTimeout.element), "Open button not found")
        XCTAssertTrue(openButton.isEnabled, "Open button should be enabled")
    }

    @MainActor
    func testFormatPickerDefaultsToPlantUML() throws {
        // A PopUpButton identified as `formatPicker` — not a RadioGroup labelled
        // "Format", which matched nothing and let the old `guard … else { return }`
        // pass this test without asserting.
        let formatPicker = app.popUpButtons["formatPicker"]
        XCTAssertTrue(
            formatPicker.waitForExistence(timeout: UITestTimeout.element),
            "Format picker should exist in Developer mode"
        )
        // Prefix, not equality: M14 relabelled the option "PlantUML (planttext.com)"
        // to disclose the third-party upload at the point of choice.
        let selected = formatPicker.value as? String ?? ""
        XCTAssertTrue(
            selected.hasPrefix("PlantUML"),
            "PlantUML should be selected by default, got '\(selected)'"
        )
    }

    /// The direct build defaults to PlantUML, but a user who declined planttext.com starts in
    /// Mermaid rather than meeting the consent card again on every launch.
    @MainActor
    func testDeclinedPlantUMLConsentStartsInMermaid() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += ["-appMode", "Developer"]
        app.launchArguments += UITestLaunchArguments.plantUMLConsentDeclined
        app.launch()

        let formatPicker = app.popUpButtons["formatPicker"]
        XCTAssertTrue(
            formatPicker.waitForExistence(timeout: UITestTimeout.element),
            "Format picker should exist in Developer mode"
        )
        let startsInMermaid = expectation(
            for: NSPredicate(format: "value BEGINSWITH 'Mermaid'"), evaluatedWith: formatPicker
        )
        wait(for: [startsInMermaid], timeout: UITestTimeout.element)
    }

    /// Settings offers the PlantUML consent toggle, off while the decision is undecided. The test
    /// does not click it: that would write the app's stored defaults.
    @MainActor
    func testSettingsShowsPlantUMLConsentToggle() throws {
        app.typeKey(",", modifierFlags: .command)

        let toggle = app.descendants(matching: .any).matching(identifier: "plantUMLConsentToggle").firstMatch
        XCTAssertTrue(
            toggle.waitForExistence(timeout: UITestTimeout.element),
            "Settings should offer the PlantUML consent toggle"
        )
        let isOff = (toggle.value as? Int) == 0 || (toggle.value as? String) == "0"
        XCTAssertTrue(
            isOff, "The toggle should be off while consent is undecided, got \(String(describing: toggle.value))"
        )
    }

    @MainActor
    func testDepthStepperAppearsInSequenceMode() throws {
        let modePicker = app.outlines["modePicker"]
        XCTAssertTrue(modePicker.waitForExistence(timeout: UITestTimeout.element))
        modePicker.staticTexts["Sequence Diagram"].click()

        let stepper = app.steppers["depthStepper"]
        XCTAssertTrue(
            stepper.waitForExistence(timeout: UITestTimeout.element),
            "Depth stepper should appear in Sequence Diagram mode"
        )
    }

    @MainActor
    func testNoSourceSelectedLabelOnLaunch() throws {
        XCTAssertTrue(
            app.staticTexts["No source selected"].waitForExistence(timeout: UITestTimeout.element),
            "Path summary should show 'No source selected' on launch"
        )
    }

    @MainActor
    func testModePickerExists() throws {
        let modePicker = app.outlines["modePicker"]
        XCTAssertTrue(modePicker.waitForExistence(timeout: UITestTimeout.element), "Mode picker should exist")
        XCTAssertTrue(
            modePicker.outlineRows.count >= 3,
            "Mode picker should have at least 3 options"
        )
    }
}
