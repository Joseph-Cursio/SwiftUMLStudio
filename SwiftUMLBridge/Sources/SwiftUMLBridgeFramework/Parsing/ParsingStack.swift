import Foundation
import Synchronization

/// Runs a parse on a thread with a stack big enough for it (#71).
///
/// SwiftParser, the `SyntaxVisitor` walks over its tree and the SourceKit typename supplement
/// each recurse once per level of nesting in the source. A nested call costs about 6.5 KB of
/// stack in a release build and about 28 KB in a debug one. Swift concurrency runs the CLI's
/// commands, Studio's detached tasks and Swift Testing's tests on cooperative threads with
/// 512 KB stacks, so 18 nested calls crashed a debug build and 55 a release one, with SIGBUS or
/// SIGILL and no diagram.
enum ParsingStack {
    /// The stack a parsing thread gets: room for SwiftParser's deepest nesting (its cap is 256
    /// levels in release) and for SourceKit's response to the same source, many times over.
    /// Only the pages a parse touches are committed.
    static let size = 64 << 20

    /// The result of `body`, run on a thread with a stack of `size` bytes, or on this thread when
    /// its stack is already that big. The calling thread waits for it, as it would have waited
    /// for the parse.
    ///
    /// `body` is escaping because the `Thread` keeps its block after the block returns, which
    /// `withoutActuallyEscaping` traps on.
    static func run<T: Sendable>(_ body: @escaping @Sendable () -> T) -> T {
        if Thread.current.stackSize >= size {
            return body()
        }
        let result = Mutex<T?>(nil)
        let finished = DispatchSemaphore(value: 0)
        let thread = Thread {
            let value = body()
            result.withLock { $0 = value }
            finished.signal()
        }
        thread.name = "SwiftUMLBridge.ParsingStack"
        thread.stackSize = size
        thread.start()
        finished.wait()
        guard let value = result.withLock({ $0 }) else {
            preconditionFailure("the parsing thread signalled before it stored its result")
        }
        return value
    }
}
