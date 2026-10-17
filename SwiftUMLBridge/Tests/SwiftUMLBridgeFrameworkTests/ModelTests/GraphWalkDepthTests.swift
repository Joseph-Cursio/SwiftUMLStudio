import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// `detectCycles` and the component layering each recursed once per node on their path, on
/// whatever thread called them. Swift Testing runs a test on a cooperative thread with a 512 KB
/// stack, as the CLI runs its commands and Studio its detached tasks, so a cycle of 379 types
/// overflowed it in a debug build, and about 3,000 in a release one, and took the whole process
/// down with it (#149). Both walks keep their own path now.
@Suite("Graph walks hold a long chain on a cooperative thread")
struct GraphWalkDepthTests {
    static let length = 10_000

    /// `class Root: Q9999`, `protocol Q1: Root`, `protocol Q<i>: Q<i-1>`: one cycle through every
    /// node, so a depth-first search from any node goes `length` deep, whatever its start order.
    static let ring: [DependencyEdge] = [
        DependencyEdge(from: "Root", to: "Q\(length - 1)", kind: .inherits),
        DependencyEdge(from: "Q1", to: "Root", kind: .conforms)
    ] + (2..<length).map { DependencyEdge(from: "Q\($0)", to: "Q\($0 - 1)", kind: .conforms) }

    /// `class C<i>: C<i-1>`, listed from the bottom up, so a search that starts at the first node
    /// it meets goes the whole chain deep.
    static let chain: [DependencyEdge] = (1..<length).reversed().map {
        DependencyEdge(from: "C\($0)", to: "C\($0 - 1)", kind: .inherits)
    }

    /// The other tests show the fix only on a stack this small. On an 8 MB thread they would
    /// pass either way.
    @Test("these tests run on a stack small enough that the search overflowed it")
    func smallStack() {
        #expect(Thread.current.stackSize <= 1 << 20)
    }

    @Test("detectCycles finds every node of a long ring")
    func ring() {
        #expect(DependencyGraphModel(edges: Self.ring).detectCycles().count == Self.length)
    }

    @Test("detectCycles finds nothing on a long chain")
    func chain() {
        #expect(DependencyGraphModel(edges: Self.chain).detectCycles().isEmpty)
    }

    @Test("detectCycles holds a long ring in a detached task, as Studio's analysis calls it")
    func ringInDetachedTask() async {
        let count = await Task.detached(priority: .userInitiated) {
            DependencyGraphModel(edges: Self.ring).detectCycles().count
        }.value
        #expect(count == Self.length)
    }

    /// SVG calls `detectCycles` a second time, from `LayoutGraphBuilder.buildDependencyGraph`.
    /// Every format but SVG. `DepsScript` runs `detectCycles` before it looks at the format, so
    /// SVG adds only the dagre layout, and a ring this long is past what JavaScriptCore can lay
    /// out on any stack: it spent about two minutes and then drew the grid. Long graphs in the
    /// layout have their own tests, `DagreLayoutDepthTests` (#150).
    @Test("a deps script of a long ring is written in every text format",
          arguments: DiagramFormat.allCases.filter { $0 != .svg })
    func depsScript(format: DiagramFormat) {
        let script = DepsScript(model: DependencyGraphModel(edges: Self.ring),
                                configuration: Configuration(format: format))
        #expect(!script.text.isEmpty)
    }

    /// Components listed with the top of the chain first, as `swift package describe` lists a
    /// chain whose names sort the other way, so the cache never cuts the walk short.
    @Test("a component layout of a long target chain has a row for each target")
    func componentChain() {
        let names = (0..<Self.length).reversed().map { String(format: "T%05d", $0) }
        let model = ComponentModel(
            components: names.map { Component(name: $0, kind: .library) },
            dependencies: (1..<Self.length).map {
                ComponentDependency(from: String(format: "T%05d", $0), to: String(format: "T%05d", $0 - 1))
            }
        )
        let levels = ComponentSVGRenderer.dependencyLevels(for: model)
        #expect(levels.count == Self.length)
        #expect(levels.first == ["T09999"])
        #expect(levels.last == ["T00000"])
    }
}

/// Checks the iterative walks against the definitions they replaced, on many small random
/// graphs with cycles and self-loops.
@Suite("Graph walks give the same answers as the definitions they replaced")
struct GraphWalkParityTests {

    /// SplitMix64, so every run tries the same graphs.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }
    }

    private static func randomPairs(
        using generator: inout SeededGenerator
    ) -> (names: [String], pairs: [(String, String)]) {
        let names = (0..<Int.random(in: 1...9, using: &generator)).map { "N\($0)" }
        let pairs = (0..<Int.random(in: 0...14, using: &generator)).map { _ in
            (names.randomElement(using: &generator) ?? "N0", names.randomElement(using: &generator) ?? "N0")
        }
        return (names.shuffled(using: &generator), pairs)
    }

    /// A node is on a cycle exactly when it can reach itself.
    private static func nodesThatReachThemselves(_ pairs: [(String, String)]) -> Set<String> {
        var adjacency: [String: [String]] = [:]
        for (source, target) in pairs {
            adjacency[source, default: []].append(target)
        }
        return Set(adjacency.keys.filter { start in
            var seen = Set<String>()
            var queue = adjacency[start] ?? []
            while let next = queue.popLast() {
                if next == start { return true }
                if seen.insert(next).inserted {
                    queue += adjacency[next] ?? []
                }
            }
            return false
        })
    }

    /// The recursive layering `ComponentSVGRenderer.dependencyLevels` used before #149.
    private static func recursiveLevels(for model: ComponentModel) -> [[String]] {
        let names = model.components.map(\.name)
        if names.isEmpty { return [] }
        var adjacency: [String: [String]] = [:]
        for dependency in model.dependencies {
            adjacency[dependency.from, default: []].append(dependency.to)
        }
        var depthCache: [String: Int] = [:]
        func depth(of name: String, visiting: Set<String>) -> Int {
            if let cached = depthCache[name] { return cached }
            if visiting.contains(name) { return 0 }
            let downstream = adjacency[name] ?? []
            if downstream.isEmpty {
                depthCache[name] = 0
                return 0
            }
            let result = 1 + (downstream
                .map { depth(of: $0, visiting: visiting.union([name])) }
                .max() ?? 0)
            depthCache[name] = result
            return result
        }
        let depths = names.map { (name: $0, depth: depth(of: $0, visiting: [])) }
        let maxDepth = depths.map(\.depth).max() ?? 0
        var rows = Array(repeating: [String](), count: maxDepth + 1)
        for entry in depths {
            rows[maxDepth - entry.depth].append(entry.name)
        }
        return rows
    }

    @Test("detectCycles returns exactly the nodes that reach themselves")
    func cycleMembership() {
        var generator = SeededGenerator(state: 149)
        for _ in 0..<2_000 {
            let (_, pairs) = Self.randomPairs(using: &generator)
            let edges = pairs.map { DependencyEdge(from: $0.0, to: $0.1, kind: .imports) }
            let found = DependencyGraphModel(edges: edges).detectCycles()
            #expect(found == Self.nodesThatReachThemselves(pairs), "\(pairs)")
        }
    }

    @Test("the component layering gives the same rows as the recursive walk")
    func componentLevels() {
        var generator = SeededGenerator(state: 149)
        for _ in 0..<2_000 {
            let (names, pairs) = Self.randomPairs(using: &generator)
            let model = ComponentModel(
                components: names.map { Component(name: $0, kind: .library) },
                dependencies: pairs.map { ComponentDependency(from: $0.0, to: $0.1) }
            )
            #expect(ComponentSVGRenderer.dependencyLevels(for: model) == Self.recursiveLevels(for: model),
                    "\(names) \(pairs)")
        }
    }
}
