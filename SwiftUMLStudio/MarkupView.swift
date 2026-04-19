import SwiftUI
import SwiftUMLBridgeFramework

struct MarkupView: View {
    let viewModel: DiagramViewModel

    var body: some View {
        Group {
            if let script = viewModel.currentScript {
                TextEditor(text: .constant(script.text))
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.background)
                    .disabled(true)
            } else {
                ContentUnavailableView("No diagram generated", systemImage: "doc.text")
            }
        }
    }
}
