//
//  DiagramViewModelMockTests.swift
//  SwiftUMLStudioTests
//
//  Unit tests for DiagramViewModel using mock diagram generators
//  to verify generation dispatch, argument forwarding, and format propagation.
//

import Foundation
import SwiftData
import Testing
@testable import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio

// MARK: - GCD dispatch helpers

private func runOnMain(_ block: @MainActor () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated(block)
    } else {
        DispatchQueue.main.sync { MainActor.assumeIsolated(block) }
    }
}

// MARK: - Mock Generators

/// A mock class diagram generator that records calls and returns a canned DiagramScript.
final class MockClassGenerator: ClassDiagramGenerating, @unchecked Sendable {
    private(set) var generateCallCount = 0
    private(set) var lastPaths: [String] = []
    private(set) var lastConfiguration: Configuration?

    func generateScript(
        for paths: [String],
        with configuration: Configuration,
        sdkPath: String?
    ) -> DiagramScript {
        generateCallCount += 1
        lastPaths = paths
        lastConfiguration = configuration
        let items = SyntaxStructure.create(from: "class MockClass {}")?.substructure ?? []
        return DiagramScript(items: items, configuration: configuration)
    }
}

/// A mock sequence diagram generator that records calls and returns canned results.
final class MockSequenceGenerator: SequenceDiagramGenerating, @unchecked Sendable {
    private(set) var generateCallCount = 0
    private(set) var findEntryPointsCallCount = 0
    private(set) var lastPaths: [String] = []
    private(set) var lastEntryType: String = ""
    private(set) var lastEntryMethod: String = ""
    private(set) var lastDepth: Int = 0
    private(set) var lastConfiguration: Configuration?

    var cannedEntryPoints: [String] = ["AppDelegate.application", "ViewModel.loadData"]

    func findEntryPoints(for paths: [String]) -> [String] {
        findEntryPointsCallCount += 1
        lastPaths = paths
        return cannedEntryPoints
    }

    func generateScript(
        for paths: [String],
        entryType: String,
        entryMethod: String,
        depth: Int,
        with configuration: Configuration
    ) -> SequenceScript {
        generateCallCount += 1
        lastPaths = paths
        lastEntryType = entryType
        lastEntryMethod = entryMethod
        lastDepth = depth
        lastConfiguration = configuration
        return .empty
    }
}

/// A mock component diagram generator that records calls and returns a canned ComponentScript.
final class MockComponentGenerator: ComponentDiagramGenerating, @unchecked Sendable {
    private(set) var generateCallCount = 0
    private(set) var lastDescription: SPMPackageDescription?
    private(set) var lastPackageRoot: URL?
    private(set) var lastConfiguration: Configuration?

    func generateScript(
        forPackage description: SPMPackageDescription,
        packageRoot: URL,
        with configuration: Configuration
    ) -> ComponentScript {
        generateCallCount += 1
        lastDescription = description
        lastPackageRoot = packageRoot
        lastConfiguration = configuration
        let model = ComponentModel(
            components: [Component(name: "MockTarget", kind: .library)],
            dependencies: []
        )
        return ComponentScript(model: model, configuration: configuration)
    }
}

/// A mock dependency graph generator that records calls and returns a canned DepsScript.
final class MockDepsGenerator: DependencyGraphGenerating, @unchecked Sendable {
    private(set) var generateCallCount = 0
    private(set) var lastPaths: [String] = []
    private(set) var lastMode: DepsMode?
    private(set) var lastConfiguration: Configuration?

    func generateScript(
        for paths: [String],
        mode: DepsMode,
        with configuration: Configuration
    ) -> DepsScript {
        generateCallCount += 1
        lastPaths = paths
        lastMode = mode
        lastConfiguration = configuration
        let model = DependencyGraphModel(edges: [])
        return DepsScript(model: model, configuration: configuration)
    }
}

// MARK: - DiagramViewModel Mock Generation Tests

@Suite("DiagramViewModel Mock Generation")
struct DiagramViewModelMockTests {

    // MARK: - Class Diagram Generation

    @Test("class diagram generation calls mock generator with correct paths")
    @MainActor
    func classDiagramCallsMockGenerator() async throws {
        let mockClass = MockClassGenerator()
        let viewModel = DiagramViewModel(
            persistenceController: PersistenceController(inMemory: true),
            classGenerator: mockClass
        )
        viewModel.selectedPaths = ["/tmp/Foo.swift", "/tmp/Bar.swift"]
        viewModel.diagramMode = .classDiagram
        viewModel.diagramFormat = .plantuml

        viewModel.generate()
        await viewModel.currentTask?.value

        #expect(mockClass.generateCallCount == 1)
        #expect(mockClass.lastPaths == ["/tmp/Foo.swift", "/tmp/Bar.swift"])
        #expect(viewModel.script != nil)
        #expect(viewModel.script?.text.contains("MockClass") == true)
        #expect(viewModel.isGenerating == false)
    }

    @Test("class diagram generation sets script via currentScript")
    @MainActor
    func classDiagramSetsCurrentScript() async throws {
        let mockClass = MockClassGenerator()
        let viewModel = DiagramViewModel(
            persistenceController: PersistenceController(inMemory: true),
            classGenerator: mockClass
        )
        viewModel.selectedPaths = ["/tmp/Foo.swift"]
        viewModel.diagramMode = .classDiagram

        viewModel.generate()
        await viewModel.currentTask?.value

        #expect(viewModel.currentScript != nil)
        #expect(viewModel.currentScript?.text == viewModel.script?.text)
    }

    // MARK: - Sequence Diagram Generation

    @Test("sequence diagram generation calls mock with correct entry type and method")
    @MainActor
    func sequenceDiagramCallsMockGenerator() async throws {
        let mockSequence = MockSequenceGenerator()
        let viewModel = DiagramViewModel(
            persistenceController: PersistenceController(inMemory: true),
            sequenceGenerator: mockSequence
        )
        viewModel.selectedPaths = ["/tmp/Foo.swift"]
        viewModel.diagramMode = .sequenceDiagram
        viewModel.entryPoint = "AppController.start"
        viewModel.sequenceDepth = 5
        viewModel.diagramFormat = .plantuml

        viewModel.generate()
        await viewModel.currentTask?.value

        #expect(mockSequence.generateCallCount == 1)
        #expect(mockSequence.lastEntryType == "AppController")
        #expect(mockSequence.lastEntryMethod == "start")
        #expect(mockSequence.lastDepth == 5)
        #expect(mockSequence.lastPaths == ["/tmp/Foo.swift"])
        #expect(viewModel.sequenceScript != nil)
        #expect(viewModel.isGenerating == false)
    }

    @Test("sequence diagram generation with default depth uses sequenceDepth value")
    @MainActor
    func sequenceDiagramUsesConfiguredDepth() async throws {
        let mockSequence = MockSequenceGenerator()
        let viewModel = DiagramViewModel(
            persistenceController: PersistenceController(inMemory: true),
            sequenceGenerator: mockSequence
        )
        viewModel.selectedPaths = ["/tmp/Foo.swift"]
        viewModel.diagramMode = .sequenceDiagram
        viewModel.entryPoint = "Foo.bar"
        viewModel.sequenceDepth = 7

        viewModel.generate()
        await viewModel.currentTask?.value

        #expect(mockSequence.lastDepth == 7)
    }

    // MARK: - Dependency Graph Generation

    @Test("dependency graph generation calls mock with correct mode")
    @MainActor
    func depsGraphCallsMockGenerator() async throws {
        let mockDeps = MockDepsGenerator()
        let viewModel = DiagramViewModel(
            persistenceController: PersistenceController(inMemory: true),
            depsGenerator: mockDeps
        )
        viewModel.selectedPaths = ["/tmp/Sources/"]
        viewModel.diagramMode = .dependencyGraph
        viewModel.depsMode = .modules
        viewModel.diagramFormat = .plantuml

        viewModel.generate()
        await viewModel.currentTask?.value

        #expect(mockDeps.generateCallCount == 1)
        #expect(mockDeps.lastPaths == ["/tmp/Sources/"])
        #expect(mockDeps.lastMode == .modules)
        #expect(viewModel.depsScript != nil)
        #expect(viewModel.isGenerating == false)
    }

    @Test("dependency graph with types mode forwards mode correctly")
    @MainActor
    func depsGraphTypesMode() async throws {
        let mockDeps = MockDepsGenerator()
        let viewModel = DiagramViewModel(
            persistenceController: PersistenceController(inMemory: true),
            depsGenerator: mockDeps
        )
        viewModel.selectedPaths = ["/tmp/Foo.swift"]
        viewModel.diagramMode = .dependencyGraph
        viewModel.depsMode = .types

        viewModel.generate()
        await viewModel.currentTask?.value

        #expect(mockDeps.lastMode == .types)
    }

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
}
