import SwiftUI

/// The history list rows shared by `HistorySidebar` and the Explorer sidebar's
/// "History" section: an empty-state placeholder, or each item with a
/// delete context menu. Designed to be embedded directly in a `List` or
/// `Section` so the enclosing selection (via `.tag`) keeps working.
struct HistoryListContent: View {
    let viewModel: DiagramViewModel

    var body: some View {
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
}
