import Foundation

/// `work`, run in a detached task at user-initiated priority, and cancelled when the task that
/// awaits it is (#236).
///
/// A detached task takes on no cancellation from the task awaiting it, so a generation that
/// `DiagramViewModel.generate()` replaced ran to its end, a full run's CPU each, and on a very
/// large project held a thread of the cooperative pool the newest run waited for. With the cancel
/// passed on, the Bridge's parses see it (`ParsingStack.callerIsCancelled`) and parse nothing
/// more, so the replaced run ends soon after, and its result is dropped as before.
nonisolated func cancellableDetached<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    let task = Task.detached(priority: .userInitiated, operation: work)
    return await withTaskCancellationHandler {
        await task.value
    } onCancel: {
        task.cancel()
    }
}
