//
//  SwiftUMLStudioUITests.swift
//  SwiftUMLStudioUITests
//
//  Created by joe cursio on 2/26/26.
//

import XCTest

final class SwiftUMLStudioUITests: XCTestCase {

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

    // MARK: - Mode switching

    /// Switching to Sequence Diagram mode exercises the conditional toolbar items
    /// (entry-point TextField and depth Stepper) and the "Enter an entry point" right-pane branch.
    @MainActor
    func testSequenceDiagramModeShowsEntryPointControls() throws {
        // Switch to Sequence Diagram mode (mode picker is a RadioGroup on macOS)
        let modePicker = app.radioGroups["modePicker"]
        XCTAssertTrue(modePicker.waitForExistence(timeout: 3), "Mode picker not found")
        modePicker.radioButtons["Sequence Diagram"].click()

        // Entry-point text field must appear in the toolbar
        let entryField = app.textFields["entryPointField"]
        XCTAssertTrue(entryField.waitForExistence(timeout: 2), "Entry point text field not found")

        // Right pane must show the entry-point prompt (entryPoint is empty at launch)
        XCTAssertTrue(
            app.staticTexts["entryPointPrompt"].waitForExistence(timeout: 2),
            "Entry point prompt not shown in right pane"
        )
    }

    /// Typing in the entry-point field clears the entry-point prompt and shows the
    /// default "Select Swift source files" placeholder instead.
    @MainActor
    func testSequenceDiagramEntryPointTypingUpdatesPlaceholder() throws {
        app.radioGroups["modePicker"].radioButtons["Sequence Diagram"].click()

        let entryField = app.textFields["entryPointField"]
        XCTAssertTrue(entryField.waitForExistence(timeout: 3), "Entry point text field not found")
        entryField.click()
        entryField.typeText("MyClass.myMethod")

        // Once entry point is non-empty the right pane switches to the file-selection prompt
        XCTAssertTrue(
            app.staticTexts["fileSelectionPrompt"].waitForExistence(timeout: 2),
            "File selection prompt not shown after entry point typed"
        )
    }

    /// Switching to Dependency Graph mode exercises the conditional Deps Mode
    /// picker in the toolbar.
    @MainActor
    func testDependencyGraphModeShowsDepsModeControls() throws {
        // Switch to Dependency Graph mode
        let modePicker = app.radioGroups["modePicker"]
        XCTAssertTrue(modePicker.waitForExistence(timeout: 3), "Mode picker not found")
        modePicker.radioButtons["Dependency Graph"].click()

        // Deps Mode picker must appear (also a RadioGroup on macOS)
        XCTAssertTrue(
            app.radioGroups["depsModeControl"].waitForExistence(timeout: 2),
            "Deps mode control not found"
        )
    }

    /// Switching between modes verifies that sequence-only controls disappear when
    /// leaving Sequence Diagram mode.
    @MainActor
    func testModeControlsAreExclusiveToTheirMode() throws {
        let modePicker = app.radioGroups["modePicker"]
        XCTAssertTrue(modePicker.waitForExistence(timeout: 3))

        // Sequence diagram controls should not be visible in Class Diagram mode (default)
        XCTAssertFalse(
            app.textFields["entryPointField"].exists,
            "Entry point field should not exist in Class Diagram mode"
        )
        XCTAssertFalse(
            app.radioGroups["depsModeControl"].exists,
            "Deps mode control should not exist in Class Diagram mode"
        )

        // Switch to Sequence Diagram — entry point controls appear, deps controls absent
        modePicker.radioButtons["Sequence Diagram"].click()
        XCTAssertTrue(app.textFields["entryPointField"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.radioGroups["depsModeControl"].exists)

        // Switch to Dependency Graph — entry point controls gone, deps controls appear
        modePicker.radioButtons["Dependency Graph"].click()
        XCTAssertFalse(
            app.textFields["entryPointField"].exists,
            "Entry point field should not exist in Dependency Graph mode"
        )
        XCTAssertTrue(app.radioGroups["depsModeControl"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testEntryPointMenuAppearsInSequenceMode() throws {
        let modePicker = app.radioGroups["modePicker"]
        XCTAssertTrue(modePicker.waitForExistence(timeout: 3), "Mode picker not found")
        modePicker.radioButtons["Sequence Diagram"].click()

        // Verify the entry point menu chevron is present
        let menu = app.menuButtons["entryPointMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 2), "Entry point menu not found in Sequence Diagram mode")
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
