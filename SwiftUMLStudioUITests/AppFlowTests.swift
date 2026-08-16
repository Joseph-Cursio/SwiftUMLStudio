import XCTest

final class AppFlowTests: XCTestCase {

    @MainActor
    func testMainUIElements() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-appMode", "Developer"]
        app.launch()

        // Sidebar tabs
        XCTAssertTrue(app.radioButtons["Files"].exists)
        XCTAssertTrue(app.radioButtons["History"].exists)

        // Toolbar + detail area
        XCTAssertTrue(app.buttons["Open…"].exists)
        XCTAssertTrue(app.buttons["Save"].exists)
        XCTAssertTrue(app.staticTexts["No source selected"].exists)

        // Mode picker
        let modePicker = app.outlines["modePicker"]
        XCTAssertTrue(modePicker.waitForExistence(timeout: UITestTimeout.element))

        // Switch to Sequence — entry-point field should appear
        modePicker.staticTexts["Sequence Diagram"].click()
        XCTAssertTrue(app.textFields["entryPointField"].waitForExistence(timeout: UITestTimeout.element))

        // Switch to Dependency — deps-mode control should appear
        modePicker.staticTexts["Dependency Graph"].click()
        XCTAssertTrue(app.radioGroups["depsModeControl"].waitForExistence(timeout: UITestTimeout.element))
    }

    @MainActor
    func testSidebarHistory() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-appMode", "Developer"]
        app.launch()

        let historyTab = app.radioButtons["History"]
        XCTAssertTrue(historyTab.waitForExistence(timeout: UITestTimeout.element))
        historyTab.click()

        // If there are history items, verify interaction
        let historyList = app.tables.firstMatch
        if historyList.exists && historyList.cells.count > 0 {
            let firstItem = historyList.cells.element(boundBy: 0)
            XCTAssertTrue(firstItem.exists)
            firstItem.click()

            firstItem.rightClick()
            XCTAssertTrue(app.menuItems["Delete"].exists)
        }
    }
}
