import SwiftUI

struct SequenceControlsView: View {
    @Bindable var viewModel: DiagramViewModel

    var body: some View {
        EntryPointPicker(
            viewModel: viewModel,
            fieldIdentifier: "entryPointField",
            menuIdentifier: "entryPointMenu"
        )

        Stepper(
            "Depth: \(viewModel.sequenceDepth)",
            value: $viewModel.sequenceDepth,
            in: 1...10
        )
        .frame(width: 120)
        .accessibilityIdentifier("depthStepper")
    }
}
