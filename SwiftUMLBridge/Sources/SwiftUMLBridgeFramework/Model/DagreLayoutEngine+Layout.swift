import Foundation
import JavaScriptCore

extension DagreLayoutEngine {
    /// Lay out the graph, returning a new graph with positions set.
    ///
    /// graphre.js recurses once per rank when it orders the nodes, and once per level of its
    /// spanning tree when it ranks them, and JavaScriptCore gives a script no more stack than the
    /// thread has. On the 512 KB cooperative threads the CLI, Studio's detached tasks and Swift
    /// Testing call this from, a chain of 660 classes overflowed it, the script threw, and the
    /// graph fell back to the grid (#150). So the layout runs on `ParsingStack`'s thread, where
    /// JavaScriptCore's own cap of about 5 MB is the limit: a chain of about 8,400 classes.
    public static func layout(_ graph: LayoutGraph) -> LayoutGraph {
        guard !graph.nodes.isEmpty else { return graph }
        return ParsingStack.run { layoutOnThisThread(graph) }
    }

    /// A context that logs what a script throws, and keeps it in `exception` as the default
    /// handler does, for `fallbackReason`. Without a handler a thrown error only made
    /// `evaluateScript` return `undefined`, and the grid fallback was the only sign of it.
    static func makeContext() -> JSContext? {
        let context = JSContext()
        context?.exceptionHandler = { context, exception in
            context?.exception = exception
            BridgeLogger.shared.error("DagreLayoutEngine: \(exception?.toString() ?? "unknown exception")")
        }
        return context
    }
}
