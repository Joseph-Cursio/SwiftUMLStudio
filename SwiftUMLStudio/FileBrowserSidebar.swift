import SwiftUI

struct FileBrowserSidebar: View {
    @Bindable var viewModel: DiagramViewModel

    var body: some View {
        List(selection: $viewModel.selectedFileURL) {
            Section("Files") {
                if viewModel.fileTree.isEmpty {
                    ContentUnavailableView("No files opened", systemImage: "doc")
                } else {
                    OutlineGroup(viewModel.fileTree, children: \.children) { node in
                        Label(node.name, systemImage: node.isDirectory ? "folder" : "swift")
                            .tag(node.url)
                    }
                }
            }
        }
        .accessibilityIdentifier("fileBrowser")
    }
}
