//
//  DiagramViewModelMockFormatTests.swift
//  SwiftUMLStudioTests
//
//  Format-propagation, refreshEntryPoints, and component-diagram dispatch
//  tests for DiagramViewModel. Split out of DiagramViewModelMockTests.swift;
//  the mock generators live there and are shared across the test target.
//

import Foundation
@testable import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

@Suite("DiagramViewModel Mock Format & Dispatch")
struct DiagramViewModelMockFormatTests {

    // MARK: - Format Propagation

    @Test("mermaid format propagates to class diagram mock configuration")
    @MainActor
    func mermaidFormatPropagatesClassDiagram() async throws {
        let mockClass = MockClassGenerator()
        let viewModel = DiagramViewModel(
            persistenceController: PersistenceController(inMemory: true),
            classGenerator: mockClass
        )
        viewModel.selectedPaths = ["/tmp/Foo.swift"]
        viewModel.diagramMode = .classDiagram
        viewModel.diagramFormat = .mermaid

        viewModel.generate()
        await viewModel.currentTask?.value

        #expect(mockClass.lastConfiguration?.format == .mermaid)
    }

    @Test("nomnoml format propagates to dependency graph mock configuration")
    @MainActor
    func nomnomlFormatPropagatesToDepsGraph() async throws {
        let mockDeps = MockDepsGenerator()
        let viewModel = DiagramViewModel(
            persistenceController: PersistenceController(inMemory: true),
            depsGenerator: mockDeps
        )
        viewModel.selectedPaths = ["/tmp/Foo.swift"]
        viewModel.diagramMode = .dependencyGraph
        viewModel.diagramFormat = .nomnoml

        viewModel.generate()
        await viewModel.currentTask?.value

        #expect(mockDeps.lastConfiguration?.format == .nomnoml)
    }

    @Test("mermaid format propagates to sequence diagram mock configuration")
    @MainActor
    func mermaidFormatPropagatesToSequence() async throws {
        let mockSequence = MockSequenceGenerator()
        let viewModel = DiagramViewModel(
            persistenceController: PersistenceController(inMemory: true),
            sequenceGenerator: mockSequence
        )
        viewModel.selectedPaths = ["/tmp/Foo.swift"]
        viewModel.diagramMode = .sequenceDiagram
        viewModel.entryPoint = "Foo.bar"
        viewModel.diagramFormat = .mermaid

        viewModel.generate()
        await viewModel.currentTask?.value

        #expect(mockSequence.lastConfiguration?.format == .mermaid)
    }

    // MARK: - refreshEntryPoints Uses Mock

    @Test("refreshEntryPoints calls mock sequence generator findEntryPoints")
    @MainActor
    func refreshEntryPointsUsesMock() {
        let mockSequence = MockSequenceGenerator()
        mockSequence.cannedEntryPoints = ["Controller.viewDidLoad", "Service.fetch"]
        let viewModel = DiagramViewModel(
            persistenceController: PersistenceController(inMemory: true),
            sequenceGenerator: mockSequence
        )
        viewModel.selectedPaths = ["/tmp/Foo.swift"]

        viewModel.refreshEntryPoints()

        #expect(mockSequence.findEntryPointsCallCount == 1)
        #expect(viewModel.availableEntryPoints == ["Controller.viewDidLoad", "Service.fetch"])
    }

    @Test("refreshEntryPoints with empty paths does not call mock")
    @MainActor
    func refreshEntryPointsEmptyPathsSkipsMock() {
        let mockSequence = MockSequenceGenerator()
        let viewModel = DiagramViewModel(
            persistenceController: PersistenceController(inMemory: true),
            sequenceGenerator: mockSequence
        )
        viewModel.selectedPaths = []

        viewModel.refreshEntryPoints()

        #expect(mockSequence.findEntryPointsCallCount == 0)
        #expect(viewModel.availableEntryPoints.isEmpty)
    }

    // MARK: - Component Diagram Generation

    /// Returns a non-empty SPM description suitable for stubbing
    /// `viewModel.packageDescription` so component generation can run without
    /// shelling out to `swift package describe`.
    private func stubPackageDescription() -> SPMPackageDescription {
        SPMPackageDescription(
            name: "Demo",
            targets: [
                SPMTargetDescription(
                    name: "Demo", kind: .library,
                    path: "Sources/Demo", sources: ["Foo.swift"], dependencies: []
                )
            ]
        )
    }

    @Test("component diagram without a loaded package surfaces an error and skips the generator")
    @MainActor
    func componentDiagramWithoutPackageSetsErrorMessage() async throws {
        let mockComponent = MockComponentGenerator()
        let viewModel = DiagramViewModel(
            persistenceController: PersistenceController(inMemory: true),
            componentGenerator: mockComponent
        )
        viewModel.diagramMode = .componentDiagram

        viewModel.generate()
        await viewModel.currentTask?.value

        #expect(mockComponent.generateCallCount == 0)
        #expect(viewModel.componentScript == nil)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.isGenerating == false)
    }

    @Test("component diagram with a loaded package calls mock and forwards format")
    @MainActor
    func componentDiagramCallsMockGenerator() async throws {
        let mockComponent = MockComponentGenerator()
        let viewModel = DiagramViewModel(
            persistenceController: PersistenceController(inMemory: true),
            componentGenerator: mockComponent
        )
        let root = URL(fileURLWithPath: "/tmp/demo-package")
        viewModel.packageRoot = root
        viewModel.packageDescription = stubPackageDescription()
        viewModel.diagramMode = .componentDiagram
        viewModel.diagramFormat = .mermaid

        viewModel.generate()
        await viewModel.currentTask?.value

        #expect(mockComponent.generateCallCount == 1)
        #expect(mockComponent.lastPackageRoot == root)
        #expect(mockComponent.lastDescription?.name == "Demo")
        #expect(mockComponent.lastConfiguration?.format == .mermaid)
        #expect(viewModel.componentScript != nil)
        #expect(viewModel.currentScript?.text == viewModel.componentScript?.text)
        #expect(viewModel.isGenerating == false)
    }
}
