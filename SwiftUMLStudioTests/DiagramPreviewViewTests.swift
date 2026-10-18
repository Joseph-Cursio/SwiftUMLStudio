import Foundation
import SwiftUI
import Testing
import ViewInspector
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio

@Suite("DiagramPreviewView")
@MainActor
struct DiagramPreviewViewTests {

    /// The consent card the preview shows. Depth-first, so the search reaches the
    /// card before the Export menu beside it, whose own state is not hosted.
    private func consentCard(in view: DiagramPreviewView) async throws -> PlantUMLConsentCard {
        try await view.inspectHosted { view in
            try view.find(ViewType.View<PlantUMLConsentCard>.self, traversal: .depthFirst).actualView()
        }
    }

    @Test("empty paths in class-diagram mode show the file-selection prompt")
    func fileSelectionPrompt() async throws {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        try await DiagramPreviewView(viewModel: viewModel).inspectHosted { view in
            _ = try view.find(viewWithAccessibilityIdentifier: "fileSelectionPrompt")
        }
    }

    @Test("sequence mode without an entry point shows the entry-point prompt")
    func entryPointPrompt() async throws {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.diagramMode = .sequenceDiagram
        viewModel.entryPoint = ""
        try await DiagramPreviewView(viewModel: viewModel).inspectHosted { view in
            _ = try view.find(viewWithAccessibilityIdentifier: "entryPointPrompt")
        }
    }

    @Test("generating state renders a ProgressView")
    func generatingState() async throws {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.isGenerating = true
        try await DiagramPreviewView(viewModel: viewModel).inspectHosted { view in
            #expect((try? view.find(ViewType.ProgressView.self)) != nil)
        }
    }

    @Test("low-confidence state machine surfaces the banner above the preview")
    func lowConfidenceBannerAppears() async throws {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.diagramMode = .stateMachine
        viewModel.stateIdentifier = "H.E"
        viewModel.availableStateMachines = [
            StateMachineModel(
                hostType: "H", enumType: "E",
                states: [], transitions: [],
                confidence: .low, notes: ["no switch"]
            )
        ]
        try await DiagramPreviewView(viewModel: viewModel).inspectHosted { view in
            _ = try view.find(viewWithAccessibilityIdentifier: "stateMachineConfidenceBanner")
        }
    }

    @Test("high-confidence state machine does not show the banner")
    func highConfidenceBannerHidden() async throws {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.diagramMode = .stateMachine
        viewModel.stateIdentifier = "H.E"
        viewModel.availableStateMachines = [
            StateMachineModel(
                hostType: "H", enumType: "E",
                states: [], transitions: [],
                confidence: .high, notes: []
            )
        ]
        try await DiagramPreviewView(viewModel: viewModel).inspectHosted { view in
            #expect(throws: InspectionError.self) {
                try view.find(viewWithAccessibilityIdentifier: "stateMachineConfidenceBanner")
            }
        }
    }

    // MARK: - PlantUML consent

    @Test("a reopened PlantUML history item asks before it is sent anywhere")
    func restoredPlantUMLAsks() async throws {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.diagramFormat = .plantuml
        viewModel.restoredScript = SimpleDiagramScript(text: "@startuml\nclass Foo\n@enduml", format: .plantuml)
        let consent = PlantUMLConsentTestSupport.makeConsent()
        let view = DiagramPreviewView(viewModel: viewModel, consent: consent)

        let card = try await consentCard(in: view)
        #expect(card.isFallback == false)
    }

    @Test("a PlantUML script under another picked format asks, and says why it is PlantUML")
    func fallbackPlantUMLAsks() async throws {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.diagramFormat = .nomnoml
        viewModel.restoredScript = SimpleDiagramScript(text: "@startuml\n[App]\n@enduml", format: .plantuml)
        let consent = PlantUMLConsentTestSupport.makeConsent()
        let view = DiagramPreviewView(viewModel: viewModel, consent: consent)

        #expect(try await consentCard(in: view).isFallback)
    }

    /// Asked of `DiagramWebView`, which picks the card. Searching the whole preview
    /// for it would also read the Export menu beside it, whose state is not hosted.
    @Test("a Mermaid script never shows the consent card")
    func mermaidDoesNotAsk() async throws {
        let script = SimpleDiagramScript(text: "classDiagram\nclass Foo", format: .mermaid)
        let consent = PlantUMLConsentTestSupport.makeConsent()
        let view = DiagramWebView(script: script, requestedFormat: .mermaid, consent: consent)

        try await view.inspectHosted { view in
            #expect((try? view.find(PlantUMLConsentCard.self)) == nil)
        }
    }

    @Test("without a source to regenerate from, the card offers no Mermaid switch")
    func noMermaidSwitchWithoutSource() async throws {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.restoredScript = SimpleDiagramScript(text: "@startuml\nclass Foo\n@enduml", format: .plantuml)
        let consent = PlantUMLConsentTestSupport.makeConsent()
        let view = DiagramPreviewView(viewModel: viewModel, consent: consent)

        #expect(try await consentCard(in: view).onUseMermaid == nil)
    }

    @Test("Use Mermaid Instead declines, switches to Mermaid and regenerates")
    func useMermaidSwitchesAndRegenerates() async throws {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.selectedPaths = ["/tmp/Foo.swift"]
        viewModel.diagramFormat = .plantuml
        viewModel.restoredScript = SimpleDiagramScript(text: "@startuml\nclass Foo\n@enduml", format: .plantuml)
        let consent = PlantUMLConsentTestSupport.makeConsent()
        let view = DiagramPreviewView(viewModel: viewModel, consent: consent)
        defer { viewModel.currentTask?.cancel() }

        let useMermaid = try #require(try await consentCard(in: view).onUseMermaid)
        useMermaid()

        #expect(consent.decision == .declined)
        #expect(viewModel.diagramFormat == .mermaid)
        #expect(viewModel.restoredScript == nil)
        #expect(viewModel.isGenerating)
    }
}
