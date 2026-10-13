import SwiftUMLBridgeFramework

/// The view model's part in the PlantUML consent flow. The decision itself is ``PlantUMLConsent``,
/// and it is checked where planttext.com is contacted — ``PlantTextPreview``.
extension DiagramViewModel {

    #if APP_STORE_BUILD
    // Default to Mermaid in the sandbox build so new users don't ship their
    // diagram source to planttext.com on first launch.
    static let buildDefaultFormat: DiagramFormat = .mermaid
    #else
    // The direct build keeps PlantUML for backward compatibility; its preview
    // still waits for consent like every other PlantUML preview.
    static let buildDefaultFormat: DiagramFormat = .plantuml
    #endif

    /// Whether ``generate()`` has a source to build from. Without one it would clear a reopened
    /// history item's script and leave an empty preview.
    var canRegenerate: Bool {
        !selectedPaths.isEmpty || packageDescription != nil
    }

    /// Switches to Mermaid, which renders on this Mac, and regenerates.
    ///
    /// It calls ``generate()`` itself because the picker may already read Mermaid — a reopened
    /// item whose saved text is PlantUML — and then the format's `onChange` never fires. When it
    /// does fire, its second `generate()` just restarts this one.
    func switchToMermaid() {
        diagramFormat = .mermaid
        generate()
    }

    /// Starts a PlantUML-default build in Mermaid when the user declined planttext.com, so they
    /// are not asked again on every launch.
    ///
    /// Called once at launch rather than from `init`: tests build view models without injecting a
    /// consent store, and reading ``PlantUMLConsent/shared`` there would tie them to the
    /// developer's own decision.
    func applyLaunchFormatPreference(consent: PlantUMLConsent) {
        if diagramFormat == .plantuml && consent.decision == .declined {
            diagramFormat = .mermaid
        }
    }
}
