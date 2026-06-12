import SwiftUI

/// The `Type.method` entry-point field plus a menu of discovered entry points,
/// shared by the activity and sequence control bars. The accessibility
/// identifiers are passed in so each host keeps its own UI-test selectors.
struct EntryPointPicker: View {
    @Bindable var viewModel: DiagramViewModel
    let fieldIdentifier: String
    let menuIdentifier: String

    var body: some View {
        HStack(spacing: 2) {
            TextField("Type.method", text: $viewModel.entryPoint)
                .frame(width: 140)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier(fieldIdentifier)

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
            .accessibilityIdentifier(menuIdentifier)
            .help("Select from discovered entry points")
        }
    }
}
