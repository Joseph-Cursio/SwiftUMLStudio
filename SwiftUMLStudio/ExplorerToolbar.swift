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

        Text(pathSummary)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: 300, alignment: .leading)

        Spacer()

        Picker("App Mode", selection: $appMode) {
            ForEach(AppMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 200)
        .accessibilityIdentifier("appModePicker")

        Button("Save to History", systemImage: "bookmark", action: onSave)
        .keyboardShortcut("s", modifiers: .command)
        .help("Save to history (⌘S)")
        .disabled(saveDisabled)
    }
}
