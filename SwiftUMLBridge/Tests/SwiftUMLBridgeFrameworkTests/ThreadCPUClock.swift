import Foundation
@testable import SwiftUMLBridgeFramework

/// The CPU time a thread spends on some work, in seconds.
///
/// A thread's CPU clock (`CLOCK_THREAD_CPUTIME_ID`) counts only the time the thread runs, not the
/// time it waits for a core. So a limit read from it holds on a busy machine and on a shared CI
/// runner, where the wall clock failed limits with the code unchanged (#237). A cost that
/// explodes is CPU work, which it still counts.
///
/// It misses work handed to another thread. `ParsingStack.run` parses on a thread of its own when
/// the caller's stack is too small, so time a parse with `onParsingThread`. SourceKit works on
/// threads of its own too, so its time can be read only by the wall clock (`WallClockLimit`).
enum ThreadCPUClock {
    /// The CPU time this thread spends running `body`.
    static func seconds(_ body: () throws -> Void) rethrows -> Double {
        let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        try body()
        return Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start) / 1e9
    }

    /// `body`'s result, and the CPU time it took, run inside `ParsingStack.run`. A parse `body`
    /// starts then runs on the thread being timed, as `run` stays on a thread whose stack is
    /// already big enough.
    static func onParsingThread<Result: Sendable>(
        _ body: @escaping @Sendable () -> Result
    ) -> (result: Result, seconds: Double) {
        ParsingStack.run {
            var result: Result?
            let seconds = Self.seconds { result = body() }
            guard let result else { preconditionFailure("body returned no result") }
            return (result, seconds)
        }
    }
}
