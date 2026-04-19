//
//  DiagramViewModelMockStateTests.swift
//  SwiftUMLStudioTests
//
//  Unit tests for DiagramViewModel mock tests covering empty-path guards,
//  debounce cancellation, state transitions, and mode isolation.
//

import Foundation
import SwiftData
import Testing
@testable import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio

// MARK: - DiagramViewModel Mock State Tests

@Suite("DiagramViewModel Mock State and Guards")
struct DiagramViewModelMockStateTests {

    // MARK: - Empty Paths Guard

    @Test("mock class generator not called when paths are empty")
    @MainActor
    func mockNotCalledWhenPathsEmpty() async throws {
        let mockClass = MockClassGenerator()
        let viewModel = DiagramViewModel(
            persistenceController: PersistenceController(inMemory: true),
            classGenerator: mockClass
        )
        viewModel.selectedPaths = []
        viewModel.diagramMode = .classDiagram

        viewModel.generate()
        try await Task.sleep(for: .milliseconds(500))

        #expect(mockClass.generateCallCount == 0)
        #expect(viewModel.script == nil)
    }

    @Test("mock deps generator not called when paths are empty")
    @MainActor
    func mockDepsNotCalledWhenPathsEmpty() async throws {
        let mockDeps = MockDepsGenerator()
        let viewModel = DiagramViewModel(
            persistenceController: PersistenceController(inMemory: true),
            depsGenerator: mockDeps
        )
        viewModel.selectedPaths = []
        viewModel.diagramMode = .dependencyGraph

        viewModel.generate()
        try await Task.sleep(for: .milliseconds(500))

        #expect(mockDeps.generateCallCount == 0)
    }

    @Test("mock sequence generator not called when entry point is empty")
    @MainActor
    func mockSequenceNotCalledWhenEntryPointEmpty() async throws {
        let mockSequence = MockSequenceGenerator()
        let viewModel = DiagramViewModel(
            persistenceController: PersistenceController(inMemory: true),
            sequenceGenerator: mockSequence
        )
        viewModel.selectedPaths = ["/tmp/Foo.swift"]
        viewModel.diagramMode = .sequenceDiagram
        viewModel.entryPoint = ""

        viewModel.generate()
        try await Task.sleep(for: .milliseconds(500))

        #expect(mockSequence.generateCallCount == 0)
    }

    // MARK: - Debounce Cancellation

    @Test("rapid generate calls result in only one generation completing")
    @MainActor
    func debounceCancelsEarlierGeneration() async throws {
        let mockClass = MockClassGenerator()
        let viewModel = DiagramViewModel(
            persistenceController: PersistenceController(inMemory: true),
            classGenerator: mockClass
        )
        viewModel.selectedPaths = ["/tmp/First.swift"]
        viewModel.diagramMode = .classDiagram

        viewModel.generate()
        viewModel.selectedPaths = ["/tmp/Second.swift"]
        viewModel.generate()

        try await Task.sleep(for: .milliseconds(500))

        #expect(mockClass.generateCallCount == 1)
        #expect(mockClass.lastPaths == ["/tmp/Second.swift"])
    }

    @Test("three rapid generate calls result in only the last completing")
    @MainActor
    func tripleDebounce() async throws {
        let mockClass = MockClassGenerator()
        let viewModel = DiagramViewModel(
            persistenceController: PersistenceController(inMemory: true),
            classGenerator: mockClass
        )
        viewModel.diagramMode = .classDiagram

        viewModel.selectedPaths = ["/tmp/A.swift"]
        viewModel.generate()
        viewModel.selectedPaths = ["/tmp/B.swift"]
        viewModel.generate()
        viewModel.selectedPaths = ["/tmp/C.swift"]
        viewModel.generate()

        try await Task.sleep(for: .milliseconds(500))

        #expect(mockClass.generateCallCount == 1)
        #expect(mockClass.lastPaths == ["/tmp/C.swift"])
    }

    // MARK: - State Transitions

    @Test("generate sets isGenerating to true immediately")
    @MainActor
    func generateSetsIsGeneratingTrue() {
        let mockClass = MockClassGenerator()
        let viewModel = DiagramViewModel(
            persistenceController: PersistenceController(inMemory: true),
            classGenerator: mockClass
        )
        viewModel.selectedPaths = ["/tmp/Foo.swift"]
        viewModel.diagramMode = .classDiagram

        viewModel.generate()

        #expect(viewModel.isGenerating == true)
    }

    @Test("generate clears errorMessage")
    @MainActor
    func generateClearsErrorMessage() {
        let mockClass = MockClassGenerator()
        let viewModel = DiagramViewModel(
            persistenceController: PersistenceController(inMemory: true),
            classGenerator: mockClass
        )
        viewModel.errorMessage = "previous error"
        viewModel.selectedPaths = ["/tmp/Foo.swift"]
        viewModel.diagramMode = .classDiagram

        viewModel.generate()

        #expect(viewModel.errorMessage == nil)
    }

    @Test("generate clears restoredScript so history item is no longer displayed")
    @MainActor
    func generateClearsRestoredScript() async throws {
        let persistence = PersistenceController(inMemory: true)
        let modelContext = persistence.container.mainContext
        let mockClass = MockClassGenerator()
        let viewModel = DiagramViewModel(
            persistenceController: persistence,
            classGenerator: mockClass
        )

        let entity = DiagramEntity()
        entity.identifier = UUID()
        entity.timestamp = Date()
        entity.mode = DiagramMode.classDiagram.rawValue
        entity.format = DiagramFormat.plantuml.rawValue
        entity.scriptText = "@startuml\nclass Old\n@enduml"
        modelContext.insert(entity)
        viewModel.loadDiagram(entity)
        #expect(viewModel.currentScript?.text == "@startuml\nclass Old\n@enduml")

        viewModel.selectedPaths = ["/tmp/Foo.swift"]
        viewModel.generate()
        try await Task.sleep(for: .milliseconds(500))

        #expect(viewModel.currentScript?.text.contains("MockClass") == true)
    }

    // MARK: - Isolation Between Modes

    @Test("class diagram generation does not set sequenceScript or depsScript")
    @MainActor
    func classDiagramDoesNotSetOtherScripts() async throws {
        let mockClass = MockClassGenerator()
        let mockSequence = MockSequenceGenerator()
        let mockDeps = MockDepsGenerator()
        let viewModel = DiagramViewModel(
            persistenceController: PersistenceController(inMemory: true),
            classGenerator: mockClass,
            sequenceGenerator: mockSequence,
            depsGenerator: mockDeps
        )
        viewModel.selectedPaths = ["/tmp/Foo.swift"]
        viewModel.diagramMode = .classDiagram

        viewModel.generate()
        try await Task.sleep(for: .milliseconds(500))

        #expect(mockClass.generateCallCount == 1)
        #expect(mockSequence.generateCallCount == 0)
        #expect(mockDeps.generateCallCount == 0)
        #expect(viewModel.sequenceScript == nil)
        #expect(viewModel.depsScript == nil)
    }

    @Test("sequence diagram generation does not set script or depsScript")
    @MainActor
    func sequenceDiagramDoesNotSetOtherScripts() async throws {
        let mockClass = MockClassGenerator()
        let mockSequence = MockSequenceGenerator()
        let mockDeps = MockDepsGenerator()
        let viewModel = DiagramViewModel(
            persistenceController: PersistenceController(inMemory: true),
            classGenerator: mockClass,
            sequenceGenerator: mockSequence,
            depsGenerator: mockDeps
        )
        viewModel.selectedPaths = ["/tmp/Foo.swift"]
        viewModel.diagramMode = .sequenceDiagram
        viewModel.entryPoint = "Foo.bar"

        viewModel.generate()
        try await Task.sleep(for: .milliseconds(500))

        #expect(mockSequence.generateCallCount == 1)
        #expect(mockClass.generateCallCount == 0)
        #expect(mockDeps.generateCallCount == 0)
        #expect(viewModel.script == nil)
        #expect(viewModel.depsScript == nil)
    }

    @Test("dependency graph generation does not set script or sequenceScript")
    @MainActor
    func depsGraphDoesNotSetOtherScripts() async throws {
        let mockClass = MockClassGenerator()
        let mockSequence = MockSequenceGenerator()
        let mockDeps = MockDepsGenerator()
        let viewModel = DiagramViewModel(
            persistenceController: PersistenceController(inMemory: true),
            classGenerator: mockClass,
            sequenceGenerator: mockSequence,
            depsGenerator: mockDeps
        )
        viewModel.selectedPaths = ["/tmp/Foo.swift"]
        viewModel.diagramMode = .dependencyGraph

        viewModel.generate()
        try await Task.sleep(for: .milliseconds(500))

        #expect(mockDeps.generateCallCount == 1)
        #expect(mockClass.generateCallCount == 0)
        #expect(mockSequence.generateCallCount == 0)
        #expect(viewModel.script == nil)
        #expect(viewModel.sequenceScript == nil)
    }
}
