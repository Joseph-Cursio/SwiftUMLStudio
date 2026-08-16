import Foundation

/// Timeouts for UI-test element waits.
///
/// These were 2 and 3 seconds, which made the whole UI suite fail — all 30
/// tests — while looking like a permissions or accessibility problem: the
/// app launched, took the menu bar, and exposed no window, so every
/// "assert exists" failed and the one "assert absent" passed.
///
/// The app was not broken and accessibility was fine. Sampling the process
/// mid-test showed the main thread busy inside SwiftUI, building the main
/// window's toolbar:
///
///     _doOpenUntitled → AppWindowsController.showInitialWindows()
///       → makeMainWindow → windowDidLoad → updateToolbarBridge
///         → ToolbarBridge.makeStorage → AppKitToolbarStrategy.makeContent
///           → ViewGraph.updateOutputs → AttributeGraph
///
/// It simply had not finished by the time the waits expired. `xcodebuild
/// test` runs the app under code-coverage instrumentation (`LLVM_PROFILE_FILE`
/// and the `PERFC_*` variables appear only in that launch), and the
/// instrumented first render is far slower than a normal one. The same tests
/// pass with `-enableCodeCoverage NO` — but coverage is wanted here, since the
/// Studio target has a ≥ 70% bar that counts UI tests, so the timeouts move
/// instead.
///
/// Deliberately generous rather than tuned to the measured figure. Uninstrumented,
/// the slowest of these waits already came in at 3.4s against a 3s limit, so the
/// old values were marginal even in the best case. A wait that is too long costs
/// time only when a test is failing anyway; one that is too short costs a red
/// suite that reads like a real defect.
enum UITestTimeout {
    /// Waiting for an element to appear.
    static let element: TimeInterval = 30
}
