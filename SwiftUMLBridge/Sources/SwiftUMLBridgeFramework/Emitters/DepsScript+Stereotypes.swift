// MARK: - Stereotype map (shared across emitters)

extension DepsScript {
    /// Per-node stereotype text derived from SPM provenance. Empty when
    /// neither `targetKinds` nor per-edge module tags are present
    /// (i.e. the path-based, non-package flow).
    ///
    /// - In modules-mode + --package, the stereotype is the SPM target
    ///   kind (`library` / `executable` / `test` / `other`); external
    ///   dependencies are absent from the map.
    /// - In types-mode + --package, the stereotype is the owning module
    ///   name; types whose module is unknown (typically external parent
    ///   types) are absent from the map.
    ///
    /// Nodes are keyed by name, so where two targets each declare a `Base`
    /// and both are edge ends, they share one node, whose edge ends may
    /// carry different modules (#202). The node takes the module most of its
    /// ends carry, a tie going to the one carried first, in edge order, which
    /// follows the files' path order. So no single edge, the last one read,
    /// relabels a type every other edge means as another module's.
    static func nodeStereotypes(model: DependencyGraphModel) -> [String: String] {
        if !model.targetKinds.isEmpty {
            return model.targetKinds.mapValues { $0.rawValue }
        }
        var counts: [String: [(module: String, count: Int)]] = [:]
        func count(_ module: String?, for node: String) {
            guard let module else { return }
            if let index = counts[node]?.firstIndex(where: { $0.module == module }) {
                counts[node]?[index].count += 1
            } else {
                counts[node, default: []].append((module, 1))
            }
        }
        for edge in model.edges {
            count(edge.fromModule, for: edge.from)
            count(edge.toModule, for: edge.toNode)
        }
        // `max(by:)` keeps the last of equal elements, so it walks the tallies reversed to keep the first.
        return counts.compactMapValues { tallies in tallies.reversed().max { $0.count < $1.count }?.module }
    }
}
