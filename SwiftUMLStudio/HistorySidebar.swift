import SwiftUI

struct HistorySidebar: View {
    @Bindable var viewModel: DiagramViewModel

    var body: some View {
        List(selection: $viewModel.selectedHistoryItem) {
            if viewModel.history.isEmpty {
                ContentUnavailableView("No history yet", systemImage: "clock")
            } else {
                ForEach(viewModel.history) { item in
                    HistoryItemRow(item: item)
                        .tag(item)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                viewModel.deleteHistoryItem(item)
                            }
                        }
                }
            }
        }
        .onChange(of: viewModel.selectedHistoryItem) {
            if let item = viewModel.selectedHistoryItem {
                viewModel.loadDiagram(item)
            }
        }
    }
}
