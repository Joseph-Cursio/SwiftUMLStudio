import Foundation

/// Public lightweight representation of a parsed Swift type for project analysis.
/// Avoids exposing the internal SyntaxStructure model.
public struct TypeInfo: Sendable {
    /// The type name (e.g. "UserViewModel")
    public let name: String

    /// The declaration kind (e.g. "class", "struct", "enum", "protocol", "actor")
    public let kind: String

    /// Access level if available (e.g. "public", "internal")
    public let accessLevel: String?

    /// Names of inherited types and protocol conformances
    public let inheritedTypeNames: [String]

    /// Attribute/macro names (e.g. ["Observable", "MainActor"])
    public let attributeNames: [String]

    /// Number of direct members (properties + methods)
    public let memberCount: Int
}

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
        self.memberCount = structure.substructure?.count ?? 0
    }
}
