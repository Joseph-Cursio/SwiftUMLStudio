import SwiftUI

struct SourceEditorView: View {
    let content: String
    let hasSelection: Bool

    var body: some View {
        Group {
            if hasSelection {
                TextEditor(text: .constant(content))
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.background)
                    .disabled(true)
            } else {
                ContentUnavailableView(
                    "Select a file",
                    systemImage: "doc.text",
                    description: Text("Choose a Swift file from the browser to view its source.")
                )
            }
        }
    }
}
