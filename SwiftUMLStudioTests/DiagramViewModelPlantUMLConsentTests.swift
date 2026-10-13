import Foundation
import Testing
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio

@Suite("DiagramViewModel — PlantUML consent")
@MainActor
struct DiagramViewModelPlantUMLConsentTests {

    private func makeViewModel() -> DiagramViewModel {
        DiagramViewModel(persistenceController: .init(inMemory: true))
    }

    @Test("a new view model starts in the build's default format")
    func startsInBuildDefault() {
        #expect(makeViewModel().diagramFormat == DiagramViewModel.buildDefaultFormat)
    }

    @Test(
        "launch starts in Mermaid instead of PlantUML only after a decline",
        arguments: [
            (DiagramFormat.plantuml, PlantUMLConsent.Decision.declined, DiagramFormat.mermaid),
            (.plantuml, .undecided, .plantuml),
            (.plantuml, .granted, .plantuml),
            (.svg, .declined, .svg)
        ]
    )
    func launchFormatPreference(
        start: DiagramFormat, decision: PlantUMLConsent.Decision, expected: DiagramFormat
    ) {
        let consent = PlantUMLConsentTestSupport.makeConsent(decision)
        let viewModel = makeViewModel()
        viewModel.diagramFormat = start

        viewModel.applyLaunchFormatPreference(consent: consent)

        #expect(viewModel.diagramFormat == expected)
    }

    @Test("there is something to regenerate from only with a selection or a package")
    func canRegenerate() {
        let viewModel = makeViewModel()
        #expect(viewModel.canRegenerate == false)
        viewModel.selectedPaths = ["/tmp/Foo.swift"]
        #expect(viewModel.canRegenerate)
    }

    @Test("switching to Mermaid regenerates even when the picker already reads Mermaid")
    func switchToMermaidRegenerates() {
        let viewModel = makeViewModel()
        viewModel.selectedPaths = ["/tmp/Foo.swift"]
        viewModel.diagramFormat = .mermaid
        viewModel.restoredScript = SimpleDiagramScript(text: "@startuml\nclass Foo\n@enduml", format: .plantuml)
        defer { viewModel.currentTask?.cancel() }

        viewModel.switchToMermaid()

        #expect(viewModel.diagramFormat == .mermaid)
        #expect(viewModel.restoredScript == nil)
        #expect(viewModel.isGenerating)
    }
}
