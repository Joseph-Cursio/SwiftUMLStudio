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

    /// `NameEnds` for each name, filled the first time an edge end asks for it. A class, so
    /// `EdgeEndIds.id(of:)` can fill it without being mutating; `EdgeEndIds` starts a new one
    /// whenever it records a declaration, so no entry outlives what it was worked out from.
    final class ExtensionEnds {
        private var endsForName: [String: NameEnds] = [:]

        func ends(named name: String, in lookup: TypeLookup) -> NameEnds {
            if let known = endsForName[name] { return known }
            var ends = NameEnds()
            for candidate in lookup.declarations(named: name) where candidate.isExtension {
                guard let nodeId = candidate.nodeId else { continue }
                if let type = lookup.extendedType(named: name, from: candidate.scope, isSugared: candidate.isSugared) {
                    if ends.standIns[type.declaration] == nil { ends.standIns[type.declaration] = nodeId }
                } else if ends.fallback == nil {
                    ends.fallback = nodeId
                }
            }
            endsForName[name] = ends
            return ends
        }
    }
}
