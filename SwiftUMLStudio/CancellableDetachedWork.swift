import Foundation
import SwiftUMLBridgeFramework

/// `work`, run in a detached task at user-initiated priority, and cancelled when the task that
/// awaits it is (#236).
///
/// A detached task takes on no cancellation from the task awaiting it, so a generation that
/// `DiagramViewModel.generate()` replaced ran to its end, a full run's CPU each, and on a very
/// large project held a thread of the cooperative pool the newest run waited for. With the cancel
/// passed on, the Bridge's parses see it (`ParsingStack.callerIsCancelled`) and parse nothing
/// more, so the replaced run ends soon after, and its result is dropped as before.
///
/// Nor does a detached task take the awaiting task's `SourceReadNotices.collector`, so `work`
/// runs with it bound, or with a collector of its own that is thrown away when the awaiting task
/// has none. So no parse run through here records into the framework's process-wide list, which
/// nothing in Studio reads.
nonisolated func cancellableDetached<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    let collector = SourceReadNotices.collector ?? SourceReadNoticeCollector()
    let task = Task.detached(priority: .userInitiated) {
        SourceReadNotices.$collector.withValue(collector, operation: work)
    }
    return await withTaskCancellationHandler {
        await task.value
    } onCancel: {
        task.cancel()
    }
}
