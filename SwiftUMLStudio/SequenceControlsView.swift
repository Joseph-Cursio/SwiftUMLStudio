import SwiftUI

struct SequenceControlsView: View {
    @Bindable var viewModel: DiagramViewModel

    var body: some View {
        HStack(spacing: 2) {
            TextField("Type.method", text: $viewModel.entryPoint)
                .frame(width: 140)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("entryPointField")

            Menu("Entry Points", systemImage: "chevron.down") {
                if viewModel.availableEntryPoints.isEmpty {
                    Text("No entry points found")
                } else {
                    ForEach(viewModel.availableEntryPoints, id: \.self) { entryPoint in
                        Button(entryPoint) {
                            viewModel.entryPoint = entryPoint
                        }
                    }
                }
            }
            .labelStyle(.iconOnly)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 20)
            .accessibilityIdentifier("entryPointMenu")
            .help("Select from discovered entry points")
        }

        Stepper(
            "Depth: \(viewModel.sequenceDepth)",
            value: $viewModel.sequenceDepth,
            in: 1...10
        )
        .frame(width: 120)
        .accessibilityIdentifier("depthStepper")
    }
}
