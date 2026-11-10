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
