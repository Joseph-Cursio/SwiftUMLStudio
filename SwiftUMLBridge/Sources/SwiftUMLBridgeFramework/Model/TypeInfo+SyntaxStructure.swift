import Foundation

extension TypeInfo {
    /// Convenience init from an internal SyntaxStructure
    internal init?(from structure: SyntaxStructure) {
        guard let kind = structure.kind else { return nil }
        let kindLabel: String
        switch kind {
        case .class: kindLabel = "class"
        case .struct: kindLabel = "struct"
        case .enum: kindLabel = "enum"
        case .protocol: kindLabel = "protocol"
        case .actor: kindLabel = "actor"
        case .extension: kindLabel = "extension"
        case .macro: kindLabel = "macro"
        default: return nil
        }

        self.name = structure.name ?? "unknown"
        self.kind = kindLabel
        self.accessLevel = structure.accessibility?.rawValue
            .components(separatedBy: ".").last
        self.inheritedTypeNames = structure.inheritedTypes?.compactMap(\.name) ?? []
        self.attributeNames = structure.attributeNames
        // A typealias is no member here: nothing counted it before the parser kept them (#125).
        self.memberCount = structure.substructure?.filter { $0.kind != .typealias }.count ?? 0
    }
}
