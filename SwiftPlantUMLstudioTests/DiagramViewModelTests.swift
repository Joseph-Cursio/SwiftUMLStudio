//
//  DiagramViewModelTests.swift
//  SwiftPlantUMLstudioTests
//
//  Created by Gemini on 3/7/26.
//
// NOTE: Unit and integration tests for DiagramViewModel are in SwiftPlantUMLstudioTests.swift,
// which uses the Swift Testing framework per project convention. The generate() integration tests
// that depend on SourceKit (ClassDiagramGenerator, DependencyGraphGenerator in types mode)
// are covered by the framework test suite run via `swift test`.

import XCTest
@testable import SwiftPlantUMLstudio

/// Smoke tests for DiagramViewModel using XCTest (kept for legacy compatibility).
/// Comprehensive coverage lives in the Swift Testing suite.
@MainActor
final class DiagramViewModelXCTests: XCTestCase {

    func testSimplePropertyAssignment() {
        let vm = DiagramViewModel()
        vm.entryPoint = "Test.main"
        XCTAssertEqual(vm.entryPoint, "Test.main")
    }

    func testInitialStateBaseline() {
        let vm = DiagramViewModel()
        XCTAssertTrue(vm.selectedPaths.isEmpty)
        XCTAssertFalse(vm.isGenerating)
        XCTAssertNil(vm.currentScript)
    }
}
