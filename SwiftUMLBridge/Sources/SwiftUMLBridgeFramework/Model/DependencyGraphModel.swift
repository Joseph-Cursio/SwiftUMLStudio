import Foundation

/// A directed graph of dependency edges between Swift types or modules.
public struct DependencyGraphModel: Sendable {
    /// All edges in the dependency graph.
    public let edges: [DependencyEdge]

    /// SPM target kind keyed by target name. Populated by the
    /// `forPackage:` generator path in modules mode so emitters can render
    /// `<<library>>` / `<<executable>>` / `<<test>>` stereotypes. Empty in
    /// the path-based flow.
    public let targetKinds: [String: SPMTargetDescription.Kind]

    public init(
        edges: [DependencyEdge],
        targetKinds: [String: SPMTargetDescription.Kind] = [:]
    ) {
        self.edges = edges
        self.targetKinds = targetKinds
    }

    /// Names of the nodes on at least one cycle: every node of a strongly connected component
    /// with more than one node, and every node with an edge to itself. A node that only leads
    /// into a cycle, or is only reached from one, is not on it.
    ///
    /// Found with Tarjan's algorithm, so the answer does not depend on where the search starts.
    /// The search keeps its own stack instead of recursing: the CLI and Studio call this on a
    /// cooperative thread, whose stack a recursive search overflowed on an inheritance chain
    /// about 380 types long in a debug build and about 3,000 in a release one (#149).
    public func detectCycles() -> Set<String> {
        var search = CycleSearch(edges: edges)
        return search.run()
    }
}

/// Tarjan's strongly connected components over `DependencyGraphModel`'s edges, with the nodes
/// numbered in the order the edges first name them, and an explicit search path in place of
/// recursion.
private struct CycleSearch {
    private var names: [String] = []
    private var successors: [[Int]] = []
    private var hasSelfLoop: [Bool] = []
    /// When the search reached each node, or nil before it does.
    private var order: [Int?] = []
    private var lowLink: [Int] = []
    private var onComponentStack: [Bool] = []
    private var componentStack: [Int] = []
    /// The nodes the search is inside, deepest last, each with the next successor to follow.
    private var searchPath: [(node: Int, nextSuccessor: Int)] = []
    private var reached = 0
    private var cycleNodes = Set<String>()

    init(edges: [DependencyEdge]) {
        var numbers: [String: Int] = [:]
        for edge in edges {
            let source = number(of: edge.from, in: &numbers)
            let target = number(of: edge.to, in: &numbers)
            successors[source].append(target)
            if source == target {
                hasSelfLoop[source] = true
            }
        }
        order = Array(repeating: nil, count: names.count)
        lowLink = Array(repeating: 0, count: names.count)
        onComponentStack = Array(repeating: false, count: names.count)
    }

    private mutating func number(of name: String, in numbers: inout [String: Int]) -> Int {
        if let known = numbers[name] {
            return known
        }
        numbers[name] = names.count
        names.append(name)
        successors.append([])
        hasSelfLoop.append(false)
        return names.count - 1
    }

    mutating func run() -> Set<String> {
        for root in names.indices where order[root] == nil {
            enter(root)
            while let top = searchPath.last {
                advance(from: top)
            }
        }
        return cycleNodes
    }

    private mutating func enter(_ node: Int) {
        order[node] = reached
        lowLink[node] = reached
        reached += 1
        componentStack.append(node)
        onComponentStack[node] = true
        searchPath.append((node: node, nextSuccessor: 0))
    }

    /// Follows the next edge out of the deepest node, or leaves that node when it has none left.
    private mutating func advance(from top: (node: Int, nextSuccessor: Int)) {
        let node = top.node
        if top.nextSuccessor < successors[node].count {
            searchPath[searchPath.count - 1].nextSuccessor += 1
            let successor = successors[node][top.nextSuccessor]
            if let reachedAt = order[successor] {
                if onComponentStack[successor] {
                    lowLink[node] = min(lowLink[node], reachedAt)
                }
            } else {
                enter(successor)
            }
            return
        }
        searchPath.removeLast()
        if let parent = searchPath.last?.node {
            lowLink[parent] = min(lowLink[parent], lowLink[node])
        }
        if lowLink[node] == order[node] {
            closeComponent(at: node)
        }
    }

    /// Pops the component whose first-reached node is `root`, and keeps it if it is a cycle.
    private mutating func closeComponent(at root: Int) {
        var members: [Int] = []
        while let member = componentStack.popLast() {
            onComponentStack[member] = false
            members.append(member)
            if member == root {
                break
            }
        }
        guard members.count > 1 || hasSelfLoop[root] else { return }
        for member in members {
            cycleNodes.insert(names[member])
        }
    }
}
