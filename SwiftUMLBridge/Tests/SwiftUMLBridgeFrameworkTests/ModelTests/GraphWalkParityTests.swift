import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

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
