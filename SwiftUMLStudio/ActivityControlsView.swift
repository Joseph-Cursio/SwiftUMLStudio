import SwiftUI

struct ActivityControlsView: View {
    @Bindable var viewModel: DiagramViewModel

    var body: some View {
        EntryPointPicker(
            viewModel: viewModel,
            fieldIdentifier: "activityEntryPointField",
            menuIdentifier: "activityEntryPointMenu"
        )
    }
}
