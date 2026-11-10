import Foundation

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
    static func nodeStereotypes(model: DependencyGraphModel) -> [String: String] {
        if !model.targetKinds.isEmpty {
            return model.targetKinds.mapValues { $0.rawValue }
        }
        var result: [String: String] = [:]
        for edge in model.edges {
            if let module = edge.fromModule { result[edge.from] = module }
            if let module = edge.toModule { result[edge.to] = module }
        }
        return result
    }
}
