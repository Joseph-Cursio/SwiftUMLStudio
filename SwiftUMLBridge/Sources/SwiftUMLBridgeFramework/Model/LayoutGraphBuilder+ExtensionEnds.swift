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

    /// Where the drawn extensions written through a typealias end edges: for each type their own
    /// lookups find, the first such extension, and for each name a type outside the diagram
    /// comes to (`TypeLookup.resolvedExtendedName(named:from:isSugared:)`), the first extension of
    /// it. An extension that spells its type by the type's own name is found under that name
    /// (`NameEnds`), so only these need a pass. `EdgeEndIds` asks them only when no extension of
    /// the edge's own spelling, or of the type's own name, ends it, so `extension Describable`
    /// after `typealias Describable = CustomStringConvertible` ends an edge written
    /// `CustomStringConvertible`, as `mergeExtensions` gives both spellings one box (#125).
    struct AliasSpelledEnds {
        var standIns: [ObjectIdentifier: String] = [:]
        var fallbacks: [String: String] = [:]
    }

    /// `NameEnds` for each name, the stand-ins among extensions spelled through a module, and
    /// `AliasSpelledEnds`, each filled the first time an edge end asks for it. A class, so
    /// `EdgeEndIds.id(of:)` can fill it without being mutating; `EdgeEndIds` starts a new one
    /// whenever it records a declaration, so no entry outlives what it was worked out from.
    final class ExtensionEnds {
        private var endsForName: [String: NameEnds] = [:]
        private var qualifiedStandInsForName: [String: [ObjectIdentifier: String]] = [:]
        private var aliasSpelledEnds: AliasSpelledEnds?

        /// One pass over the drawn extensions written through a typealias, its module first or not
        /// (`extension MyModule.Describable`), in recording order. An
        /// extension whose type's name is not sure (`TypeLookup.sureResolvedName(of:from:depth:)`)
        /// is no other spelling's fallback.
        func aliasSpelled(in lookup: TypeLookup) -> AliasSpelledEnds {
            if let aliasSpelledEnds { return aliasSpelledEnds }
            var ends = AliasSpelledEnds()
            for (name, candidate) in lookup.recordedExtensions {
                guard let nodeId = candidate.nodeId else { continue }
                let scope = candidate.scope
                guard lookup.namesTypealias(name) || lookup.spellsTypealiasThroughModule(name, from: scope) else {
                    continue
                }
                if let type = lookup.extendedType(named: name, from: scope, isSugared: candidate.isSugared) {
                    if ends.standIns[type.declaration] == nil { ends.standIns[type.declaration] = nodeId }
                } else if let resolved = lookup.resolvedExtendedName(
                    named: name, from: scope, isSugared: candidate.isSugared
                ), ends.fallbacks[resolved] == nil {
                    ends.fallbacks[resolved] = nodeId
                }
            }
            aliasSpelledEnds = ends
            return ends
        }

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

        /// For each type they find, the first drawn extension spelled `<module>.<name>`, such as
        /// `extension ModA.Foo` for `Foo`, in recording order (#124).
        func qualifiedStandIns(spelling name: String, in lookup: TypeLookup) -> [ObjectIdentifier: String] {
            if let known = qualifiedStandInsForName[name] { return known }
            var standIns: [ObjectIdentifier: String] = [:]
            for (spelled, candidate) in lookup.extensions(named: lookup.moduleQualifiedNames(of: name)) {
                guard let nodeId = candidate.nodeId, let type = lookup.extendedType(
                    named: spelled, from: candidate.scope, isSugared: candidate.isSugared
                ), standIns[type.declaration] == nil else { continue }
                standIns[type.declaration] = nodeId
            }
            qualifiedStandInsForName[name] = standIns
            return standIns
        }
    }
}
