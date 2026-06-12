import SwiftUI

/// The segmented Explorer/Developer mode picker shared by the developer
/// toolbar (`ContentView`) and the Explorer toolbar (`ExplorerToolbar`).
struct AppModePicker: View {
    @Binding var appMode: AppMode

    var body: some View {
        Picker("App Mode", selection: $appMode) {
            ForEach(AppMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 200)
        .accessibilityIdentifier("appModePicker")
    }
}

/// The truncating, secondary-styled path summary shown in both toolbars.
struct PathSummaryLabel: View {
    let pathSummary: String

    var body: some View {
        Text(pathSummary)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: 300, alignment: .leading)
    }
}
