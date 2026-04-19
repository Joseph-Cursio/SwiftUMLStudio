import XCTest

final class AppFlowTests: XCTestCase {

    @MainActor
    func testMainUIElements() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-appMode", "Developer"]
        app.launch()

        // Sidebar
        XCTAssertTrue(app.staticTexts["History"].exists)

        // Check if primary elements are present in the main content/detail area
        XCTAssertTrue(app.buttons["Open…"].exists)
        XCTAssertTrue(app.buttons["Save"].exists)
        XCTAssertTrue(app.staticTexts["No source selected"].exists)

        // Mode picker
        let modePicker = app.radioGroups["Mode"]
        if modePicker.exists {
            // Initial state
            XCTAssertTrue(modePicker.radioButtons["Class Diagram"].isSelected)

            // Switch to Sequence
            modePicker.radioButtons["Sequence Diagram"].click()
            XCTAssertTrue(modePicker.radioButtons["Sequence Diagram"].isSelected)

            // Check if sequence specific elements appeared
            XCTAssertTrue(app.textFields["Type.method"].exists)

            // Switch to Dependency
            modePicker.radioButtons["Dependency Graph"].click()
            XCTAssertTrue(modePicker.radioButtons["Dependency Graph"].isSelected)

            let depsPicker = app.radioGroups["Deps Mode"]
            if depsPicker.exists {
                XCTAssertTrue(depsPicker.radioButtons["Types"].isSelected)
                depsPicker.radioButtons["Modules"].click()
                XCTAssertTrue(depsPicker.radioButtons["Modules"].isSelected)
            }
        }

        // Format picker
        let formatPicker = app.radioGroups["Format"]
        if formatPicker.exists {
            XCTAssertTrue(formatPicker.radioButtons["PlantUML"].isSelected)
            formatPicker.radioButtons["Mermaid"].click()
            XCTAssertTrue(formatPicker.radioButtons["Mermaid"].isSelected)
        }
    }

    @MainActor
    func testSidebarHistory() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-appMode", "Developer"]
        app.launch()

        let historySection = app.staticTexts["History"]
        XCTAssertTrue(historySection.exists)

        // If there are history items, verify interaction
        let historyList = app.tables.firstMatch
        if historyList.exists && historyList.cells.count > 0 {
            let firstItem = historyList.cells.element(boundBy: 0)
            XCTAssertTrue(firstItem.exists)

            // Test selection (tap/click)
            firstItem.click()

            // Test context menu (right click)
            firstItem.rightClick()
            XCTAssertTrue(app.menuItems["Delete"].exists)
        }
    }
}
