import Foundation
import SwiftUI
import Testing
import ViewInspector
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio

@Suite("DiagramPreviewView")
@MainActor
struct DiagramPreviewViewTests {

    @Test("empty paths in class-diagram mode show the file-selection prompt")
    func fileSelectionPrompt() throws {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        let view = DiagramPreviewView(viewModel: viewModel)
        _ = try view.inspect().find(viewWithAccessibilityIdentifier: "fileSelectionPrompt")
    }

    @Test("sequence mode without an entry point shows the entry-point prompt")
    func entryPointPrompt() throws {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.diagramMode = .sequenceDiagram
        viewModel.entryPoint = ""
        let view = DiagramPreviewView(viewModel: viewModel)
        _ = try view.inspect().find(viewWithAccessibilityIdentifier: "entryPointPrompt")
    }

    @Test("generating state renders a ProgressView")
    func generatingState() throws {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.isGenerating = true
        let view = DiagramPreviewView(viewModel: viewModel)
        #expect((try? view.inspect().find(ViewType.ProgressView.self)) != nil)
    }

    @Test("low-confidence state machine surfaces the banner above the preview")
    func lowConfidenceBannerAppears() throws {
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
        let view = DiagramPreviewView(viewModel: viewModel)
        _ = try view.inspect().find(viewWithAccessibilityIdentifier: "stateMachineConfidenceBanner")
    }

    @Test("high-confidence state machine does not show the banner")
    func highConfidenceBannerHidden() throws {
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
        let view = DiagramPreviewView(viewModel: viewModel)
        #expect(throws: InspectionError.self) {
            try view.inspect().find(viewWithAccessibilityIdentifier: "stateMachineConfidenceBanner")
        }
    }

    // MARK: - PlantUML consent

    @Test("a reopened PlantUML history item asks before it is sent anywhere")
    func restoredPlantUMLAsks() throws {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.diagramFormat = .plantuml
        viewModel.restoredScript = SimpleDiagramScript(text: "@startuml\nclass Foo\n@enduml", format: .plantuml)
        let consent = PlantUMLConsentTestSupport.makeConsent()
        let view = DiagramPreviewView(viewModel: viewModel, consent: consent)

        let card = try view.inspect().find(PlantUMLConsentCard.self).actualView()
        #expect(card.isFallback == false)
    }

    @Test("a PlantUML script under another picked format asks, and says why it is PlantUML")
    func fallbackPlantUMLAsks() throws {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.diagramFormat = .nomnoml
        viewModel.restoredScript = SimpleDiagramScript(text: "@startuml\n[App]\n@enduml", format: .plantuml)
        let consent = PlantUMLConsentTestSupport.makeConsent()
        let view = DiagramPreviewView(viewModel: viewModel, consent: consent)

        #expect(try view.inspect().find(PlantUMLConsentCard.self).actualView().isFallback)
    }

    @Test("a Mermaid script never shows the consent card")
    func mermaidDoesNotAsk() throws {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.restoredScript = SimpleDiagramScript(text: "classDiagram\nclass Foo", format: .mermaid)
        let consent = PlantUMLConsentTestSupport.makeConsent()
        let view = DiagramPreviewView(viewModel: viewModel, consent: consent)

        #expect((try? view.inspect().find(PlantUMLConsentCard.self)) == nil)
    }

    @Test("without a source to regenerate from, the card offers no Mermaid switch")
    func noMermaidSwitchWithoutSource() throws {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.restoredScript = SimpleDiagramScript(text: "@startuml\nclass Foo\n@enduml", format: .plantuml)
        let consent = PlantUMLConsentTestSupport.makeConsent()
        let view = DiagramPreviewView(viewModel: viewModel, consent: consent)

        #expect(try view.inspect().find(PlantUMLConsentCard.self).actualView().onUseMermaid == nil)
    }

    @Test("Use Mermaid Instead declines, switches to Mermaid and regenerates")
    func useMermaidSwitchesAndRegenerates() throws {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.selectedPaths = ["/tmp/Foo.swift"]
        viewModel.diagramFormat = .plantuml
        viewModel.restoredScript = SimpleDiagramScript(text: "@startuml\nclass Foo\n@enduml", format: .plantuml)
        let consent = PlantUMLConsentTestSupport.makeConsent()
        let view = DiagramPreviewView(viewModel: viewModel, consent: consent)
        defer { viewModel.currentTask?.cancel() }

        let useMermaid = try #require(view.inspect().find(PlantUMLConsentCard.self).actualView().onUseMermaid)
        useMermaid()

        #expect(consent.decision == .declined)
        #expect(viewModel.diagramFormat == .mermaid)
        #expect(viewModel.restoredScript == nil)
        #expect(viewModel.isGenerating)
    }
}
