import Foundation

extension Array where Element == SyntaxStructure {
    /// The structures a class diagram walks, in drawing order: nested types flattened when the
    /// configuration shows them, protocols first and extensions last, and extensions merged into
    /// their types when it asks for that. The steps below edit structures in place, so they run
    /// on a private copy: the same items always prepare to the same result, and the caller's
    /// structures are left as they were (#73).
    func preparedForClassDiagram(with configuration: Configuration) -> [SyntaxStructure] {
        var prepared = SyntaxStructure.clonedForest(of: self)
        if configuration.elements.showNestedTypes {
            prepared = prepared.populateNestedTypes()
        }
        prepared = prepared.orderedByProtocolsFirstExtensionsLast()
        if configuration.shallExtensionsBeMerged {
            let indicator = configuration.elements.mergedExtensionMemberIndicator
            prepared = prepared.mergeExtensions(mergedMemberIndicator: indicator) { $0.isDrawn(in: configuration) }
        }
        return prepared
    }

    /// order: protocols first, then non-extensions (i.e protocols, structs, classes, enums, actors). Extensions last.
    func orderedByProtocolsFirstExtensionsLast() -> [SyntaxStructure] {
        sorted(by: { $0.kind ?? .struct < $1.kind ?? .struct })
    }

    /// merges extensions with their parent types
    ///
    /// Appends each extension's members into its type's `substructure` and sets their
    /// `memberSuffix`, editing the structures in place. The extension records that type in
    /// `mergedInto`, so a type nested in it is drawn hanging off the box that shows its members,
    /// while its `parent` stays the extension that declares it, for its scope and access (#74).
    /// The type records the supertypes the extension's inheritance clause names in
    /// `carriedSupertypes`, so the conformances it declares are drawn from that box too (#76).
    /// Diagram code calls it only through `preparedForClassDiagram(with:)`, which hands it a
    /// private copy.
    /// - Parameters:
    ///   - mergedMemberIndicator: string appended as suffix to a member that originates from an extension
    ///   - isDrawn: whether the diagram draws an item; an extension of a type it hides merges into
    ///     that type's stand-in instead (#153)
    /// - Returns: new array with at most 1 extension per type
    func mergeExtensions(
        mergedMemberIndicator: String? = "<&bolt>", isDrawn: (SyntaxStructure) -> Bool = { _ in true }
    ) -> [SyntaxStructure] {
        var processedItems = self
        // Worked out before any merge, from the declarations as the sources wrote them.
        let targets = MergeTargets(of: self, isDrawn: isDrawn)

        for structure in self where structure.kind == .extension {
            guard let parent = targets.target(of: structure), structure != parent else {
                continue
            }
            processedItems.removeAll(where: { $0 == structure })
            structure.mergedInto = parent
            // Before the members guard: `extension Foo: P {}` has no members, and is the commonest form.
            let scope = DeclarationScope(of: structure)
            parent.carriedSupertypes += (structure.inheritedTypes ?? []).map {
                SyntaxStructure.CarriedSupertype(supertype: $0, scope: scope)
            }
            // A box holding `extension Foo<Int>` and `extension Foo<String>` is no longer either.
            if parent.boundGenericArguments != structure.boundGenericArguments {
                parent.boundGenericArguments = nil
            }
            guard let members = structure.substructure else { continue }
            if let memberSuffix = mergedMemberIndicator, parent.kind != .extension {
                for member in members where member.name != nil {
                    member.memberSuffix = memberSuffix
                }
            }
            if parent.substructure == nil {
                parent.substructure = []
            }
            parent.substructure?.append(contentsOf: members)
        }
        return processedItems
    }

    /// Flattens nested types into the list, setting each one's `parent` in place. Diagram code
    /// calls it only through `preparedForClassDiagram(with:)`, which hands it a private copy.
    func populateNestedTypes(parent: SyntaxStructure? = nil) -> [SyntaxStructure] {
        var items: [SyntaxStructure] = []
        for structure in self where isNestedType(structure) {
            structure.parent = parent
            items.append(structure)
            guard let substructure = structure.substructure, substructure.count > 0 else {
                continue
            }
            items.append(contentsOf: substructure.populateNestedTypes(parent: structure))
        }
        if parent == nil {
            for structure in self where !isNestedType(structure) {
                items.append(structure)
            }
        }
        return items
    }

    /// The kinds `populateNestedTypes` walks into and flattens: every `ElementKind.processable`
    /// kind but `.macro`, which is declared only at the top level and keeps its place after the
    /// types. Derived from that list so it cannot drift from it again: a hand-written copy left
    /// out `.protocol`, so a protocol nested in a type (SE-0404) was never drawn (#162).
    func isNestedType(_ structure: SyntaxStructure) -> Bool {
        guard let kind = structure.kind, kind != .macro else { return false }
        return ElementKind.processable.contains(kind)
    }
}

extension SyntaxStructure {
    /// Attribute names (e.g. ["Observable", "MainActor"]) extracted from this element's declaration.
    var attributeNames: [String] {
        attributes?.compactMap(\.attribute) ?? []
    }
}

extension SyntaxStructure {
    /// A supertype that a merged extension's inheritance clause names, and the scope of that
    /// extension, where the name is looked up.
    struct CarriedSupertype {
        let supertype: SyntaxStructure
        let scope: DeclarationScope
    }
}

extension SyntaxStructure {
    /// The item a nested type is drawn hanging off: its `parent`, or for one nested in an
    /// extension that `mergeExtensions` merged away, the item that extension merged into (#107).
    var nestingParent: SyntaxStructure? {
        parent.map { $0.mergedInto ?? $0 }
    }

    var fullName: String? {
        var qualifiedName = name
        var aParent: SyntaxStructure?
        aParent = parent
        while aParent != nil {
            qualifiedName = (aParent?.name ?? "") + "." + (qualifiedName ?? "")
            aParent = aParent?.parent
        }
        return qualifiedName
    }

    var displayName: String? {
        guard let comps = name?.components(separatedBy: ".") else { return name }
        return comps.last
    }
}

extension SyntaxStructure {
    override var debugDescription: String {
        // A structure SourceKit gave no kind or name still has to describe itself: a failing
        // test or the debugger prints it, and a trap there hides the failure being looked at.
        "\(kind?.rawValue.components(separatedBy: ".").last ?? "unknown") \(fullName ?? "<unnamed>")"
    }
}

extension ElementKind: Comparable {
    private var sortOrder: Int {
        switch self {
        case .protocol: return 0
        case .extension: return 2
        default: return 1
        }
    }

    static func < (lhs: ElementKind, rhs: ElementKind) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

/// The item each extension merges into, under `mergeExtensions`: the type its name means where it
/// is written, by the lookup `LayoutGraphBuilder` resolves edges by — the nearest type Swift's
/// access control lets it see. With no such type it extends one outside the diagram, and merges
/// into the first extension that sees none either, so that type gets one box, its first
/// extension's. A type the diagram hides has no box to merge into either: its first drawn
/// extension, one whose own lookup finds that same type, stands in for it, and the rest merge
/// there (#153). One that names the type without a module qualifier comes before one that names
/// it through its module (`extension ModA.Foo`, #124), as `EdgeEndIds.standIn` looks for them, so
/// the box keeps the type's own name, which the text formats' supertype edges end on. Extensions
/// are matched by the type their names come to, not by spelling, so `extension Alias` and
/// `extension Real` share a box after `typealias Alias = Real`, and so do `extension JSON` and
/// `extension [String: Int]` after `typealias JSON = [String: Int]` (#125).
///
/// Each extension is looked up once: finding a hidden type's first extension by looking up every
/// extension again, for each extension, was cubic on many files that each hide a same-named type.
private struct MergeTargets {
    private var targetForExtension: [ObjectIdentifier: SyntaxStructure] = [:]

    init(of items: [SyntaxStructure], isDrawn: (SyntaxStructure) -> Bool) {
        let lookup = LayoutGraphBuilder.TypeLookup(of: items)
        var typeForDeclaration: [ObjectIdentifier: SyntaxStructure] = [:]
        for item in items where item.kind != .extension {
            typeForDeclaration[ObjectIdentifier(item)] = item
        }
        var hiddenTypeOfExtension: [(item: SyntaxStructure, type: ObjectIdentifier)] = []
        var plainHost: [ObjectIdentifier: SyntaxStructure] = [:]
        var qualifiedHost: [ObjectIdentifier: SyntaxStructure] = [:]
        var outsideHost: [String: SyntaxStructure] = [:]
        for item in items where item.kind == .extension {
            guard let name = item.fullName else { continue }
            let scope = DeclarationScope(of: item)
            guard let type = lookup.type(named: name, from: scope) else {
                let resolvedName = lookup.resolvedName(of: name, from: scope)
                let host = outsideHost[resolvedName] ?? item
                outsideHost[resolvedName] = host
                targetForExtension[ObjectIdentifier(item)] = host
                continue
            }
            if let declared = typeForDeclaration[type.declaration], isDrawn(declared) {
                targetForExtension[ObjectIdentifier(item)] = declared
                continue
            }
            hiddenTypeOfExtension.append((item, type.declaration))
            guard isDrawn(item) else { continue }
            if lookup.readsModule(name, from: scope) {
                qualifiedHost[type.declaration] = qualifiedHost[type.declaration] ?? item
            } else {
                plainHost[type.declaration] = plainHost[type.declaration] ?? item
            }
        }
        for (item, type) in hiddenTypeOfExtension {
            targetForExtension[ObjectIdentifier(item)] = plainHost[type] ?? qualifiedHost[type]
        }
    }

    func target(of anExtension: SyntaxStructure) -> SyntaxStructure? {
        targetForExtension[ObjectIdentifier(anExtension)]
    }
}
