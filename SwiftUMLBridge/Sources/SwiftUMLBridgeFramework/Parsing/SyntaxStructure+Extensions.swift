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
            prepared = prepared.mergeExtensions(mergedMemberIndicator: indicator)
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
    /// `memberSuffix`, editing the structures in place. A type nested in the extension is
    /// re-parented to that type, so its edge leaves the box that shows the extension's members.
    /// Diagram code calls it only through `preparedForClassDiagram(with:)`, which hands it a
    /// private copy.
    /// - Parameter mergedMemberIndicator: string appended as suffix to a member that originates from an extension
    /// - Returns: new array with at most 1 extension per type
    func mergeExtensions(mergedMemberIndicator: String? = "<&bolt>") -> [SyntaxStructure] {
        var processedItems = self

        for structure in self where structure.kind == .extension {
            guard let parent = processedItems.mergeTarget(for: structure), structure != parent else { continue }
            processedItems.removeAll(where: { $0 == structure })
            guard let members = structure.substructure else { continue }
            if let memberSuffix = mergedMemberIndicator, parent.kind != .extension {
                for member in members where member.name != nil {
                    member.memberSuffix = memberSuffix
                }
            }
            for member in members where member.parent == structure {
                member.parent = parent
            }
            if parent.substructure == nil {
                parent.substructure = []
            }
            parent.substructure?.append(contentsOf: members)
        }
        return processedItems
    }

    /// The item `anExtension` merges into: of the types with its name, the one nearest to it as
    /// `DeclarationScope` ranks them — the rule `LayoutGraphBuilder` resolves edges by. With no
    /// such type, the first item of that name, so a type the sources only extend gets one box,
    /// its first extension's.
    private func mergeTarget(for anExtension: SyntaxStructure) -> SyntaxStructure? {
        let sameNamed = filter { $0.fullName == anExtension.fullName }
        let types = sameNamed.filter { $0.kind != .extension }
        return DeclarationScope(of: anExtension).nearest(among: types, scope: DeclarationScope.init(of:))
            ?? sameNamed.first
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

    func isNestedType(_ structure: SyntaxStructure) -> Bool {
        structure.kind == .class
            || structure.kind == .struct
            || structure.kind == .enum
            || structure.kind == .extension
            || structure.kind == .actor
    }
}

extension SyntaxStructure {
    /// Attribute names (e.g. ["Observable", "MainActor"]) extracted from this element's declaration.
    var attributeNames: [String] {
        attributes?.compactMap(\.attribute) ?? []
    }
}

extension SyntaxStructure {
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
        "\(kind!.rawValue.components(separatedBy: ".").last!) \(fullName!)"
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
