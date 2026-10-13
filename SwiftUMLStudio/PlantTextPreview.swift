import SwiftUI
import WebKit
import SwiftUMLBridgeFramework

/// The PlantUML preview, and the only place Studio contacts `planttext.com`.
///
/// It loads the rendered diagram only once ``PlantUMLConsent`` is granted, and until then shows
/// ``PlantUMLConsentCard`` in its place. Consent used to be asked when the Format picker changed
/// to PlantUML, while the request was made here for any PlantUML script — so a script that became
/// current another way was uploaded unasked: the direct build's default format, a reopened history
/// item (behind the alert, where Cancel could not take it back), the component diagram's Nomnoml
/// fallback, or a regeneration while the alert was open. Checking at the request covers every
/// route, including ones added later.
struct PlantTextPreview: View {
    let script: any DiagramOutputting
    /// The Format picker's value, so the card can explain a PlantUML script the user did not pick.
    var requestedFormat: DiagramFormat?
    let consent: PlantUMLConsent
    /// Switches the diagram to a format that renders locally; `nil` hides that choice.
    var onUseMermaid: (() -> Void)?

    enum Content: Equatable {
        /// No PlantUML text to draw, so nothing to ask about either.
        case nothing
        case consentCard
        case render(URL)
    }

    /// What the preview shows for `script`.
    ///
    /// Empty text shows nothing and asks for nothing. The Bridge's "nothing found" scripts are
    /// typed PlantUML whatever format was requested, and an empty one still built a planttext.com
    /// URL — a third-party request with Mermaid selected.
    nonisolated static func content(for script: any DiagramOutputting, isGranted: Bool) -> Content {
        guard script.format == .plantuml, !script.text.isEmpty else { return .nothing }
        guard isGranted else { return .consentCard }
        guard let url = URL(string: "https://www.planttext.com/api/plantuml/svg/\(script.encodeText())") else {
            return .nothing
        }
        return .render(url)
    }

    var body: some View {
        switch Self.content(for: script, isGranted: consent.isGranted) {
        case .render(let url):
            WebView(url: url)
        case .consentCard:
            PlantUMLConsentCard(
                isFallback: requestedFormat.map { $0 != .plantuml } ?? false,
                onAllow: consent.grant,
                onUseMermaid: onUseMermaid.map { switchToMermaid in
                    {
                        consent.decline()
                        switchToMermaid()
                    }
                }
            )
        case .nothing:
            EmptyView()
        }
    }
}

/// Asks, in place of the preview, whether to send a PlantUML diagram to `planttext.com`.
struct PlantUMLConsentCard: View {
    /// The picked format cannot draw this diagram type, so the script fell back to PlantUML.
    var isFallback: Bool
    let onAllow: () -> Void
    var onUseMermaid: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label("Preview with planttext.com?", systemImage: "network")
        } description: {
            VStack(spacing: 8) {
                Text(
                    "PlantUML previews are drawn by planttext.com, a third-party service. "
                    + "Showing this one sends its PlantUML source — type names, members and "
                    + "relationships, but no function bodies — to that service over HTTPS. "
                    + "Mermaid, Nomnoml and SVG previews are drawn on this Mac."
                )
                if isFallback {
                    Text("The selected format can't draw this diagram, so it was generated as PlantUML.")
                        .accessibilityIdentifier("plantUMLConsentFallbackNote")
                }
                Text("Exporting the source sends nothing. Studio remembers your choice.")
                    .font(.caption)
            }
        } actions: {
            Button("Preview with planttext.com", action: onAllow)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("plantUMLConsentAllowButton")
            if let onUseMermaid {
                Button("Use Mermaid Instead", action: onUseMermaid)
                    .accessibilityIdentifier("plantUMLConsentUseMermaidButton")
            }
        }
        .accessibilityIdentifier("plantUMLConsentCard")
    }
}
