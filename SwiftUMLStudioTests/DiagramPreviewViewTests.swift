import Foundation
import SwiftUI
import Testing
import ViewInspector
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio

// DiagramPreviewView doesn't read the environment, so it's straightforward to
// inspect via ViewInspector. DiagramDetailView cannot be tested here because it
// reads `@Environment(SubscriptionManager.self)` which ViewInspector does not
// propagate through its extraction path for @Observable values.

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
}
