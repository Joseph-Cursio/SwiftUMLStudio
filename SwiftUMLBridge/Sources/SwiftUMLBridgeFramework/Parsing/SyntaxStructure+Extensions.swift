import Foundation

extension Array where Element == SyntaxStructure {
    /// order: protocols first, then non-extensions (i.e protocols, structs, classes, enums, actors). Extensions last.
    func orderedByProtocolsFirstExtensionsLast() -> [SyntaxStructure] {
        sorted(by: { $0.kind ?? .struct < $1.kind ?? .struct })
    }

    /// merges extensions with their parent types
    /// - Parameter mergedMemberIndicator: string appended as suffix to a member that originates from an extension
    /// - Returns: new array with at most 1 extension per type
    func mergeExtensions(mergedMemberIndicator: String? = "<&bolt>") -> [SyntaxStructure] {
        var processedItems = self

        for structure in self where structure.kind == .extension {
            guard let parentIndex = processedItems.firstIndex(where: { $0.fullName == structure.fullName }) else {
                continue
            }
            let parent = processedItems[parentIndex]
            guard structure != parent else { continue }
            processedItems.removeAll(where: { $0 == structure })
            guard let members = structure.substructure else { continue }
            if let memberSuffix = mergedMemberIndicator, parent.kind != .extension {
                for index in members.indices {
                    guard members[index].name != nil else { continue }
                    members[index].memberSuffix = memberSuffix
                }
            }
            if parent.substructure == nil {
                parent.substructure = []
            }
            parent.substructure?.append(contentsOf: members)
            processedItems[parentIndex] = parent
        }
        return processedItems
    }

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

    private func isNestedType(_ structure: SyntaxStructure) -> Bool {
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
