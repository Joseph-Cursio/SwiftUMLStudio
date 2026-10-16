import Foundation
import SwiftParser
import SwiftSyntax
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

    /// How deep SwiftParser follows nesting before it reads the rest of the file as unexpected
    /// tokens, so that no declaration after that point is seen: its release default, in debug
    /// builds too. Their own default of 20 dropped the rest of a file 20 levels in, so `swift run`,
    /// `swift test` and a Debug Studio read less than a release build. A debug build's parser
    /// needs about 28 KB of stack a level, so 256 levels fit in `size`.
    static let maximumNestingLevel = 256

    /// `source` parsed as a Swift file, as deep as `maximumNestingLevel`. Call it inside `run`.
    static func parse(_ source: String) -> SourceFileSyntax {
        var parser = Parser(source, maximumNestingLevel: maximumNestingLevel)
        return SourceFileSyntax.parse(from: &parser)
    }

    /// The result of `body`, run on a thread with a stack of `size` bytes, or on this thread when
    /// its stack is already that big. The calling thread waits for it, as it would have waited
    /// for the parse, and the parsing thread runs at the calling thread's quality of service: a
    /// semaphore lends the waiting thread's priority to no one, so a thread left at the default
    /// would have demoted Studio's user-initiated generation and promoted background work.
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
        thread.qualityOfService = Thread.current.qualityOfService
        thread.stackSize = size
        thread.start()
        finished.wait()
        guard let value = result.withLock({ $0 }) else {
            preconditionFailure("the parsing thread signalled before it stored its result")
        }
        return value
    }
}
