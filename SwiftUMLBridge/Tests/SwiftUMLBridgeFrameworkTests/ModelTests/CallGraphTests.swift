@testable import SwiftUMLBridgeFramework
import Testing

@Suite("CallGraph")
struct CallGraphTests {

    // MARK: - Helpers

    private func edge(
        callerType: String, callerMethod: String,
        calleeType: String?, calleeMethod: String,
        isAsync: Bool = false, isUnresolved: Bool = false
    ) -> CallEdge {
        CallEdge(
            callerType: callerType,
            callerMethod: callerMethod,
            calleeType: calleeType,
            calleeMethod: calleeMethod,
            isAsync: isAsync,
            isUnresolved: isUnresolved
        )
    }

    // MARK: - Empty and entry-point-not-found

    @Test("empty graph returns no edges")
    func emptyGraphReturnsNoEdges() {
        let graph = CallGraph(edges: [])
        let result = graph.traverse(from: "Foo", entryMethod: "run", maxDepth: 3)
        #expect(result.isEmpty)
    }

    @Test("entry point not found returns empty result")
    func entryPointNotFoundReturnsEmpty() {
        let graph = CallGraph(edges: [
            edge(callerType: "Bar", callerMethod: "go", calleeType: "Baz", calleeMethod: "finish")
        ])
        let result = graph.traverse(from: "Foo", entryMethod: "run", maxDepth: 3)
        #expect(result.isEmpty)
    }

    @Test("maxDepth zero returns no edges")
    func maxDepthZeroReturnsNoEdges() {
        // Entry at depth 0, guard is `depth < maxDepth` → 0 < 0 is false, nothing is processed.
        let graph = CallGraph(edges: [
            edge(callerType: "Foo", callerMethod: "run", calleeType: "Bar", calleeMethod: "process")
        ])
        let result = graph.traverse(from: "Foo", entryMethod: "run", maxDepth: 0)
        #expect(result.isEmpty)
    }

    // MARK: - Basic traversal

    @Test("single hop returns the one matching edge")
    func singleHopReturnsOneEdge() {
        let graph = CallGraph(edges: [
            edge(callerType: "Foo", callerMethod: "run", calleeType: "Bar", calleeMethod: "process")
        ])
        let result = graph.traverse(from: "Foo", entryMethod: "run", maxDepth: 3)
        #expect(result.count == 1)
        #expect(result[0].calleeType == "Bar")
        #expect(result[0].calleeMethod == "process")
    }

    @Test("multiple callees from same caller all appear in result")
    func multipleCalleesAllAppear() {
        let graph = CallGraph(edges: [
            edge(callerType: "Foo", callerMethod: "run", calleeType: "Bar", calleeMethod: "a"),
            edge(callerType: "Foo", callerMethod: "run", calleeType: "Bar", calleeMethod: "b"),
            edge(callerType: "Foo", callerMethod: "run", calleeType: "Baz", calleeMethod: "c"),
        ])
        let result = graph.traverse(from: "Foo", entryMethod: "run", maxDepth: 3)
        #expect(result.count == 3)
    }

    @Test("two-hop chain traverses both levels")
    func twoHopChainTraversesBothLevels() {
        let graph = CallGraph(edges: [
            edge(callerType: "A", callerMethod: "start", calleeType: "B", calleeMethod: "step"),
            edge(callerType: "B", callerMethod: "step", calleeType: "C", calleeMethod: "finish"),
        ])
        let result = graph.traverse(from: "A", entryMethod: "start", maxDepth: 3)
        let methods = result.map(\.calleeMethod)
        #expect(methods.contains("step"))
        #expect(methods.contains("finish"))
    }

    @Test("same-type call chain is traversed correctly")
    func sameTypeCallChain() {
        let graph = CallGraph(edges: [
            edge(callerType: "Service", callerMethod: "run", calleeType: "Service", calleeMethod: "step"),
            edge(callerType: "Service", callerMethod: "step", calleeType: "Service", calleeMethod: "done"),
        ])
        let result = graph.traverse(from: "Service", entryMethod: "run", maxDepth: 3)
        let methods = result.map(\.calleeMethod)
        #expect(methods.contains("step"))
        #expect(methods.contains("done"))
    }

    // MARK: - Depth limiting

    @Test("depth 1 includes only direct callees of the entry method")
    func depthOneLimitsToDirectCallees() {
        // Chain: A.start → B.step → C.finish
        // With maxDepth=1: A.start processed at depth 0 (0 < 1 ✓), B.step enqueued at depth 1.
        // B.step dequeued at depth 1 (1 < 1 ✗) → skipped.
        let graph = CallGraph(edges: [
            edge(callerType: "A", callerMethod: "start", calleeType: "B", calleeMethod: "step"),
            edge(callerType: "B", callerMethod: "step", calleeType: "C", calleeMethod: "finish"),
        ])
        let result = graph.traverse(from: "A", entryMethod: "start", maxDepth: 1)
        let methods = result.map(\.calleeMethod)
        #expect(methods.contains("step"))
        #expect(methods.contains("finish") == false)
    }

    @Test("depth 2 includes two call levels but not the third")
    func depthTwoIncludesTwoLevelsNotThird() {
        // Chain: A.run → B.b → C.c → D.d
        let graph = CallGraph(edges: [
            edge(callerType: "A", callerMethod: "run", calleeType: "B", calleeMethod: "b"),
            edge(callerType: "B", callerMethod: "b", calleeType: "C", calleeMethod: "c"),
            edge(callerType: "C", callerMethod: "c", calleeType: "D", calleeMethod: "d"),
        ])
        let result = graph.traverse(from: "A", entryMethod: "run", maxDepth: 2)
        let methods = result.map(\.calleeMethod)
        #expect(methods.contains("b"))
        #expect(methods.contains("c"))
        #expect(methods.contains("d") == false)
    }

    // MARK: - Cycle detection

    @Test("mutual cycle A→B→A is visited only once per node")
    func mutualCycleVisitedOnce() {
        let graph = CallGraph(edges: [
            edge(callerType: "A", callerMethod: "ping", calleeType: "B", calleeMethod: "pong"),
            edge(callerType: "B", callerMethod: "pong", calleeType: "A", calleeMethod: "ping"),
        ])
        let result = graph.traverse(from: "A", entryMethod: "ping", maxDepth: 10)
        // A.ping → B.pong → A.ping (already visited) → stops. Two edges total.
        #expect(result.count == 2)
    }

    @Test("self-recursive method produces exactly one edge")
    func selfRecursiveMethodOneEdge() {
        let graph = CallGraph(edges: [
            edge(callerType: "Foo", callerMethod: "recurse", calleeType: "Foo", calleeMethod: "recurse")
        ])
        let result = graph.traverse(from: "Foo", entryMethod: "recurse", maxDepth: 10)
        // Foo.recurse visited once; its self-call enqueues Foo.recurse again, but it is already visited.
        #expect(result.count == 1)
    }

    // MARK: - Unresolved edges

    @Test("unresolved edge appears in result but its callee is not expanded")
    func unresolvedEdgeIncludedNotExpanded() {
        let graph = CallGraph(edges: [
            edge(callerType: "Foo", callerMethod: "run",
                 calleeType: nil, calleeMethod: "unknown",
                 isUnresolved: true),
            // Would be reachable if "unknown" were expanded — must NOT appear.
            edge(callerType: "Foo", callerMethod: "unknown", calleeType: "Bar", calleeMethod: "secret"),
        ])
        let result = graph.traverse(from: "Foo", entryMethod: "run", maxDepth: 5)
        let methods = result.map(\.calleeMethod)
        #expect(methods.contains("unknown"))
        #expect(methods.contains("secret") == false)
    }

    @Test("resolved and unresolved edges from same caller both appear")
    func resolvedAndUnresolvedBothIncluded() {
        let graph = CallGraph(edges: [
            edge(callerType: "Foo", callerMethod: "run", calleeType: "Bar", calleeMethod: "process"),
            edge(callerType: "Foo", callerMethod: "run",
                 calleeType: nil, calleeMethod: "unknown",
                 isUnresolved: true),
        ])
        let result = graph.traverse(from: "Foo", entryMethod: "run", maxDepth: 3)
        #expect(result.count == 2)
        let unresolved = result.filter(\.isUnresolved)
        #expect(unresolved.count == 1)
    }

    // MARK: - Async flag passthrough

    @Test("async flag is preserved on edges in the traversal result")
    func asyncFlagPreservedInResult() {
        let graph = CallGraph(edges: [
            edge(callerType: "Foo", callerMethod: "run",
                 calleeType: "Bar", calleeMethod: "load",
                 isAsync: true),
        ])
        let result = graph.traverse(from: "Foo", entryMethod: "run", maxDepth: 3)
        #expect(result.first?.isAsync == true)
    }
}
