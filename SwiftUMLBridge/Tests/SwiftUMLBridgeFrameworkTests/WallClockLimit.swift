import Foundation
import Testing

/// A limit on wall-clock time, checked only on a developer's machine.
///
/// The wall clock counts time spent waiting for a core, so on a shared CI runner, whose load no
/// one controls, these limits fail with the code unchanged (#237). Each still guards a cost that
/// explodes, such as a parse that doubles with each `[`, so they run locally, where a regression
/// is caught before it is pushed. A limit that reads the thread's CPU clock
/// (`CLOCK_THREAD_CPUTIME_ID`) counts no waiting, and stays on CI.
enum WallClockLimit {
    /// Whether wall-clock limits are checked: not when `CI` is set, as GitHub Actions sets it on
    /// every runner.
    static let isChecked = ProcessInfo.processInfo.environment["CI"] == nil

    /// Expects `elapsed` to be under `limit`, except on CI.
    static func expect(
        _ elapsed: Duration, under limit: Duration, _ comment: Comment? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard isChecked else { return }
        #expect(elapsed < limit, comment, sourceLocation: sourceLocation)
    }
}
