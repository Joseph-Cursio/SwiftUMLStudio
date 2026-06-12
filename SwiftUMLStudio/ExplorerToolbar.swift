import SwiftUI

struct ExplorerToolbar: View {
    let pathSummary: String
    @Binding var appMode: AppMode
    let onOpen: () -> Void
    let onSave: () -> Void
    let saveDisabled: Bool

    var body: some View {
        Button("Open…", systemImage: "folder", action: onOpen)
            .help("Open Swift files or directories (⌘O)")

        PathSummaryLabel(pathSummary: pathSummary)

        Spacer()

        AppModePicker(appMode: $appMode)

        Button("Save to History", systemImage: "bookmark", action: onSave)
        .keyboardShortcut("s", modifiers: .command)
        .help("Save to history (⌘S)")
        .disabled(saveDisabled)
    }
}
