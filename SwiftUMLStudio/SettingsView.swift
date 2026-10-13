import SwiftUI

/// The app's Settings window: Settings… in the app menu, ⌘,.
struct SettingsView: View {
    /// Injected by tests, which must not read or change the developer's own decision.
    var consent: PlantUMLConsent = .shared

    var body: some View {
        Form {
            Section("PlantUML") {
                Toggle("Render PlantUML previews with planttext.com", isOn: plantUMLConsentBinding)
                    .accessibilityIdentifier("plantUMLConsentToggle")
                Text(
                    "PlantUML previews are drawn by planttext.com, a third-party service, so "
                    + "showing one sends its PlantUML source there over HTTPS. When this is off, "
                    + "a PlantUML preview asks first, and Mermaid, Nomnoml and SVG are unaffected: "
                    + "they are drawn on this Mac."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// On is a grant. Off goes back to undecided rather than declined, so a direct build keeps
    /// starting in its PlantUML default instead of Mermaid. Either way the next PlantUML preview
    /// asks again.
    private var plantUMLConsentBinding: Binding<Bool> {
        Binding(
            get: { consent.isGranted },
            set: { isOn in isOn ? consent.grant() : consent.revoke() }
        )
    }
}
