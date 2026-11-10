import Foundation
import Testing

/// A limit on wall-clock time, checked only on a developer's machine.
///
/// The wall clock counts time spent waiting for a core, so on a shared CI runner, whose load no
/// one controls, a wall-clock limit fails with the code unchanged (#237). Read a thread's CPU
/// clock (`ThreadCPUClock`) instead, which counts no waiting and is checked everywhere. This is
/// for work that clock cannot see, such as SourceKit's, which runs on threads of its own: give it
/// a bound a busy machine stays far inside, and it still catches a cost that explodes before it
/// is pushed.
enum WallClockLimit {
    /// Whether wall-clock limits are checked: not when `CI` is set, as GitHub Actions sets it on
    /// every runner.
    static let isChecked = ProcessInfo.processInfo.environment["CI"] == nil

    /// Expects `elapsed` to be under `limit`, except on CI.
    static func expect(
        _ elapsed: Duration,
        under limit: Duration,
        _ comment: Comment? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard isChecked else { return }
        #expect(elapsed < limit, comment, sourceLocation: sourceLocation)
    }
}
