import Foundation
import SwiftParser
import SwiftSyntax
import Synchronization

/// Runs a parse on a thread with a stack big enough for it (#71).
///
/// SwiftParser, the `SyntaxVisitor` walks over its tree and the SourceKit typename supplement
/// each recurse once per level of nesting in the source. SwiftParser takes about 6.5 KB of stack
/// a nested call in a release build and about 26 KB in a debug one; Foundation's JSON writer,
/// which the supplement used, took about 9.7 KB. Swift concurrency runs the CLI's commands,
/// Studio's detached tasks and Swift Testing's tests on cooperative threads with 512 KB stacks,
/// so 18 nested calls crashed a debug build. A release build crashed at 55 where the supplement
/// ran and at about 80 elsewhere, with SIGBUS or SIGILL and no diagram.
///
/// `DagreLayoutEngine` runs its layout here too. graphre.js recurses once per rank, and
/// JavaScriptCore gives a script no more stack than its thread has, so on a cooperative thread a
/// chain of 660 classes made the script throw and the diagram fall back to a grid (#150).
enum ParsingStack {
    /// The stack a parsing thread gets: room for SwiftParser's deepest nesting
    /// (`maximumNestingLevel`, up to about 8 MB in a debug build) and for SourceKit's response
    /// to the same source, many times over. Only the pages a parse touches are committed.
    static let size = 64 << 20

    /// How deep SwiftParser follows nesting before it reads the rest of the file as unexpected
    /// tokens, so that nothing after that point is seen: its release default, in debug builds
    /// too. Each `(`, `[`, `{` and `#if` it is inside counts as a level. Debug builds' own default
    /// of 20 dropped the rest of a file 20 levels in, so `swift run`, `swift test` and a Debug
    /// Studio read less than a release build. A debug build's parser needs about 26 KB of stack a
    /// level, so 256 levels fit in `size`.
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
