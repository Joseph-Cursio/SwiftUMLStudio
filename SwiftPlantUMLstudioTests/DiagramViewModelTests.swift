//
//  DiagramViewModelTests.swift
//  SwiftPlantUMLstudioTests
//
//  Created by Gemini on 3/7/26.
//

import XCTest
import Foundation
import SwiftUMLBridgeFramework
@testable import SwiftPlantUMLstudio

@MainActor
final class DiagramViewModelTests: XCTestCase {

    private func createTempSwiftFile(content: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).swift")
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testSimpleSync() {
        let viewModel = DiagramViewModel()
        viewModel.entryPoint = "Test.main"
        XCTAssertEqual(viewModel.entryPoint, "Test.main")
    }

    func testInitialState() {
        let viewModel = DiagramViewModel()
        XCTAssertTrue(viewModel.selectedPaths.isEmpty)
        XCTAssertNil(viewModel.script)
        XCTAssertNil(viewModel.sequenceScript)
        XCTAssertNil(viewModel.depsScript)
        XCTAssertFalse(viewModel.isGenerating)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.diagramFormat, .plantuml)
        XCTAssertEqual(viewModel.diagramMode, .classDiagram)
        XCTAssertNil(viewModel.currentScript)
    }

    func testGenerateClassDiagram() async throws {
        let viewModel = DiagramViewModel()
        let fileURL = createTempSwiftFile(content: "class MyClass {}")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        viewModel.selectedPaths = [fileURL.path]
        viewModel.diagramMode = .classDiagram
        
        viewModel.generate()
        
        XCTAssertTrue(viewModel.isGenerating)
        
        let expectation = XCTestExpectation(description: "Generate class diagram")
        
        // Poll for completion
        for _ in 0..<50 {
            if !viewModel.isGenerating {
                expectation.fulfill()
                break
            }
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        }
        
        await fulfillment(of: [expectation], timeout: 10.0)
        
        XCTAssertFalse(viewModel.isGenerating)
        XCTAssertNotNil(viewModel.script)
        XCTAssertTrue(viewModel.script?.text.contains("class \"MyClass\"") ?? false)
    }

    func testGenerateDependencyGraph() async throws {
        let viewModel = DiagramViewModel()
        let fileURL = createTempSwiftFile(content: "class A: B {}; class B {}")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        viewModel.selectedPaths = [fileURL.path]
        viewModel.diagramMode = .dependencyGraph
        
        viewModel.generate()
        
        XCTAssertTrue(viewModel.isGenerating)
        
        let expectation = XCTestExpectation(description: "Generate dependency graph")
        
        for _ in 0..<50 {
            if !viewModel.isGenerating {
                expectation.fulfill()
                break
            }
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        }
        
        await fulfillment(of: [expectation], timeout: 10.0)
        
        XCTAssertFalse(viewModel.isGenerating)
        XCTAssertNotNil(viewModel.depsScript)
        XCTAssertTrue(viewModel.depsScript?.text.contains("A --|> B") ?? false)
    }

    func testGenerateSequenceDiagram() async throws {
        let viewModel = DiagramViewModel()
        let fileURL = createTempSwiftFile(content: "class A { func start() { B().run() } }; class B { func run() {} }")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        viewModel.selectedPaths = [fileURL.path]
        viewModel.diagramMode = .sequenceDiagram
        viewModel.entryPoint = "A.start"
        
        viewModel.generate()
        
        XCTAssertTrue(viewModel.isGenerating)
        
        let expectation = XCTestExpectation(description: "Generate sequence diagram")
        
        for _ in 0..<50 {
            if !viewModel.isGenerating {
                expectation.fulfill()
                break
            }
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        }
        
        await fulfillment(of: [expectation], timeout: 10.0)
        
        XCTAssertFalse(viewModel.isGenerating)
        XCTAssertNotNil(viewModel.sequenceScript)
        XCTAssertTrue(viewModel.sequenceScript?.text.contains("A ->> B : run") ?? false)
    }

    func testGenerateWithEmptyPaths() {
        let viewModel = DiagramViewModel()
        viewModel.selectedPaths = []
        
        viewModel.generate()
        XCTAssertFalse(viewModel.isGenerating)
        
        viewModel.diagramMode = .sequenceDiagram
        viewModel.generate()
        XCTAssertFalse(viewModel.isGenerating)
        
        viewModel.diagramMode = .dependencyGraph
        viewModel.generate()
        XCTAssertFalse(viewModel.isGenerating)
    }

    func testGenerateSequenceWithInvalidEntryPoint() {
        let viewModel = DiagramViewModel()
        let fileURL = createTempSwiftFile(content: "class A {}")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        viewModel.selectedPaths = [fileURL.path]
        viewModel.diagramMode = .sequenceDiagram
        
        // Missing entry point
        viewModel.entryPoint = ""
        viewModel.generate()
        XCTAssertFalse(viewModel.isGenerating)
        
        // Invalid format (no dot)
        viewModel.entryPoint = "A"
        viewModel.generate()
        XCTAssertFalse(viewModel.isGenerating)
    }
}
