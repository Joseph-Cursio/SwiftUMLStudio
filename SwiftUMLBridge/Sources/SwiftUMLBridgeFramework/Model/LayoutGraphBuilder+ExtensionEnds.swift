import Foundation

// MARK: - Extension Ends

/// Where `EdgeEndIds` ends an edge on a drawn extension, kept apart so the edge ends stay a
/// readable size.
extension LayoutGraphBuilder {
    /// Where the drawn extensions of one name end edges: for each type their own lookups find,
    /// the first such extension (`EdgeEndIds.standIn`), and the first that finds none
    /// (`EdgeEndIds.fallback`), each the node id of a drawn extension.
    struct NameEnds {
        var standIns: [ObjectIdentifier: String] = [:]
        var fallback: String?
    }

    /// `NameEnds` for each name, and the stand-ins among extensions spelled through a module, each
    /// filled the first time an edge end asks for it. A class, so `EdgeEndIds.id(of:)` can fill it
    /// without being mutating; `EdgeEndIds` starts a new one whenever it records a declaration,
    /// so no entry outlives what it was worked out from.
    final class ExtensionEnds {
        private var endsForName: [String: NameEnds] = [:]
        private var qualifiedStandInsForName: [String: [ObjectIdentifier: String]] = [:]

        func ends(named name: String, in lookup: TypeLookup) -> NameEnds {
            if let known = endsForName[name] { return known }
            var ends = NameEnds()
            for candidate in lookup.declarations(named: name) where candidate.isExtension {
                guard let nodeId = candidate.nodeId else { continue }
                if let type = lookup.type(named: name, from: candidate.scope) {
                    if ends.standIns[type.declaration] == nil { ends.standIns[type.declaration] = nodeId }
                } else if ends.fallback == nil {
                    ends.fallback = nodeId
                }
            }
            endsForName[name] = ends
            return ends
        }

        /// For each type they find, the first drawn extension spelled `<module>.<name>`, such as
        /// `extension ModA.Foo` for `Foo`, in recording order (#124).
        func qualifiedStandIns(spelling name: String, in lookup: TypeLookup) -> [ObjectIdentifier: String] {
            if let known = qualifiedStandInsForName[name] { return known }
            var standIns: [ObjectIdentifier: String] = [:]
            for (spelled, candidate) in lookup.extensions(named: lookup.moduleQualifiedNames(of: name)) {
                guard let nodeId = candidate.nodeId, let type = lookup.type(named: spelled, from: candidate.scope),
                      standIns[type.declaration] == nil else { continue }
                standIns[type.declaration] = nodeId
            }
            qualifiedStandInsForName[name] = standIns
            return standIns
        }

        func fallback(named name: String, in lookup: TypeLookup) -> String? {
            ends(named: name, in: lookup).fallback
        }
    }
}
