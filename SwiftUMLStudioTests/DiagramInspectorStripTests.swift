import Foundation
import SwiftUI
import Testing
import ViewInspector
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio

@Suite("DiagramInspectorStrip")
@MainActor
struct DiagramInspectorStripTests {

    private func makeViewModel(mode: DiagramMode = .classDiagram) -> DiagramViewModel {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.diagramMode = mode
        return viewModel
    }

    private func inspect(_ viewModel: DiagramViewModel) throws -> InspectableView<ViewType.ClassifiedView> {
        try DiagramInspectorStrip(viewModel: viewModel).inspect()
    }

    private func picker(
        _ identifier: String, in viewModel: DiagramViewModel
    ) throws -> InspectableView<ViewType.Picker> {
        try inspect(viewModel).find(viewWithAccessibilityIdentifier: identifier).picker()
    }

    // MARK: - Format picker

    @Test("format picker lists all four formats")
    func formatOptions() throws {
        let labels = try picker("formatPicker", in: makeViewModel())
            .findAll(ViewType.Text.self).map { try $0.string() }
        #expect(labels.starts(with: ["PlantUML (planttext.com)", "Mermaid", "Nomnoml", "SVG"]))
    }

    @Test("choosing a format writes through to the view model")
    func selectFormat() throws {
        let viewModel = makeViewModel()
        try picker("formatPicker", in: viewModel).select(value: DiagramFormat.mermaid)
        #expect(viewModel.diagramFormat == .mermaid)
    }

    // MARK: - Mode-specific controls

    @Test(
        "modes without extra controls show only the format picker",
        arguments: [DiagramMode.classDiagram, .erDiagram, .componentDiagram]
    )
    func noModeControls(mode: DiagramMode) throws {
        let view = try inspect(makeViewModel(mode: mode))
        #expect(view.findAll(ViewType.Picker.self).count == 1)
        #expect(throws: InspectionError.self) { try view.find(SequenceControlsView.self) }
        #expect(throws: InspectionError.self) { try view.find(ActivityControlsView.self) }
    }

    @Test("sequence mode shows the sequence controls")
    func sequenceControls() throws {
        _ = try inspect(makeViewModel(mode: .sequenceDiagram)).find(SequenceControlsView.self)
    }

    @Test("activity mode shows the activity controls")
    func activityControls() throws {
        _ = try inspect(makeViewModel(mode: .activityDiagram)).find(ActivityControlsView.self)
    }

    @Test("dependency mode offers every DepsMode and writes the choice through")
    func depsPicker() throws {
        let viewModel = makeViewModel(mode: .dependencyGraph)
        let picker = try picker("depsModeControl", in: viewModel)
        let labels = picker.findAll(ViewType.Text.self).map { try? $0.string() }
        for mode in DepsMode.allCases {
            #expect(labels.contains(mode.rawValue))
        }

        let other = try #require(DepsMode.allCases.first { $0 != viewModel.depsMode })
        try picker.select(value: other)
        #expect(viewModel.depsMode == other)
    }

    // MARK: - State machine picker

    private func stateMachine(_ enumType: String, confidence: DetectionConfidence) -> StateMachineModel {
        StateMachineModel(
            hostType: "Host", enumType: enumType,
            states: [], transitions: [],
            confidence: confidence, notes: []
        )
    }

    @Test("state machine picker lists candidates after a blank option")
    func stateMachineCandidates() throws {
        let viewModel = makeViewModel(mode: .stateMachine)
        viewModel.availableStateMachines = [
            stateMachine("Phase", confidence: .high),
            stateMachine("Mode", confidence: .low)
        ]
        let labels = try picker("stateMachinePicker", in: viewModel)
            .findAll(ViewType.Text.self).map { try $0.string() }
        #expect(labels.starts(with: ["—", "Host.Phase", "Host.Mode"]))
    }

    @Test("each candidate carries its confidence symbol")
    func confidenceSymbols() throws {
        let viewModel = makeViewModel(mode: .stateMachine)
        viewModel.availableStateMachines = [
            stateMachine("High", confidence: .high),
            stateMachine("Medium", confidence: .medium),
            stateMachine("Low", confidence: .low)
        ]
        let symbols = try picker("stateMachinePicker", in: viewModel)
            .findAll(ViewType.Image.self).compactMap { try? $0.actualImage().name() }
        #expect(symbols == ["circle.fill", "circle.lefthalf.filled", "exclamationmark.triangle.fill"])
    }

    @Test("choosing a state machine writes its identifier through")
    func selectStateMachine() throws {
        let viewModel = makeViewModel(mode: .stateMachine)
        viewModel.availableStateMachines = [stateMachine("Phase", confidence: .high)]
        try picker("stateMachinePicker", in: viewModel).select(value: "Host.Phase")
        #expect(viewModel.stateIdentifier == "Host.Phase")
    }
}
