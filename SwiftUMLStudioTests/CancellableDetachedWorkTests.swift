import Foundation
@testable import SwiftUMLStudio
import Testing

/// A detached task takes on no cancellation from the task awaiting it, so `cancellableDetached`
/// passes it on: a generation `generate()` replaced then stops parsing rather than running to
/// its end (#236).
@Suite("Detached work takes on the cancel of the task awaiting it")
struct CancellableDetachedWorkTests {

    /// The work waits, up to ten seconds, for its own task to be cancelled.
    @Test("cancelling the awaiting task cancels the work")
    func cancelReachesWork() async {
        let awaiting = Task {
            await cancellableDetached { () -> Bool in
                let deadline = Date().addingTimeInterval(10)
                while !Task.isCancelled, Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.001)
                }
                return Task.isCancelled
            }
        }
        awaiting.cancel()
        #expect(await awaiting.value)
    }

    @Test("work no one cancels runs to its result")
    func uncancelledWorkRuns() async {
        let result = await cancellableDetached { (1...10).reduce(0, +) }
        #expect(result == 55)
    }
}
