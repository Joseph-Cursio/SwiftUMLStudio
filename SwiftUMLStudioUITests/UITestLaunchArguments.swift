import Foundation

/// Launch arguments the UI tests pass to the app.
enum UITestLaunchArguments {
    /// Pins the PlantUML consent to undecided for the run.
    ///
    /// The UI tests launch the app with its real defaults domain, so without this the
    /// developer's own decision chose between the consent card and a planttext.com upload.
    /// Launch arguments sit in `UserDefaults`' argument domain, which wins over stored values
    /// and is never written back.
    ///
    /// The card's buttons record the decision in the stored defaults, which the argument
    /// domain only hides — a UI test must not click them. The unit tests cover what they do.
    static let plantUMLConsentUndecided = [
        "-plantUMLRenderingConsented", "NO",
        "-plantUMLRenderingDeclined", "NO"
    ]

    /// Pins the PlantUML consent to declined for the run, through the argument domain as above.
    static let plantUMLConsentDeclined = [
        "-plantUMLRenderingConsented", "NO",
        "-plantUMLRenderingDeclined", "YES"
    ]
}
