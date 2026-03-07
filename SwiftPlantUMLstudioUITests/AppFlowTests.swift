//
//  AppFlowTests.swift
//  SwiftPlantUMLstudioUITests
//
//  Created by Gemini on 3/7/26.
//

import XCTest

final class AppFlowTests: XCTestCase {

    @MainActor
    func testMainUIElements() throws {
        let app = XCUIApplication()
        app.launch()

        // Check if primary elements are present
        XCTAssertTrue(app.buttons["Open…"].exists)
        XCTAssertTrue(app.buttons["Generate"].exists)
        XCTAssertTrue(app.staticTexts["No source selected"].exists)

        // Mode picker
        let modePicker = app.radioGroups["Mode"]
        if modePicker.exists {
            XCTAssertTrue(modePicker.buttons["Class Diagram"].isSelected)
            
            modePicker.radioButtons["Sequence Diagram"].click()
            XCTAssertTrue(modePicker.radioButtons["Sequence Diagram"].isSelected)
            
            // Check if sequence specific elements appeared
            XCTAssertTrue(app.textFields["Type.method"].exists)
            XCTAssertTrue(app.steppers["Depth: 3"].exists)
            
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
}
