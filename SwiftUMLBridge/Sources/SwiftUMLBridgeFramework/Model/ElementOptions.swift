import Foundation

/// Options which and how elements shall be considered for class diagram generation
public struct ElementOptions: Codable, Sendable {
    /// Only types declared at one of these access levels are drawn.
    public private(set) var havingAccessLevel: [AccessLevel] = [.open, .public, .package, .internal, .private]
    /// Only members declared at one of these access levels are listed inside a type box.
    public private(set) var showMembersWithAccessLevel: [AccessLevel] = [.open, .public, .package, .internal, .private]
    /// Whether nested types are drawn as their own boxes.
    public private(set) var showNestedTypes: Bool = true
    /// Whether generic parameter clauses are shown in type and member signatures.
    public private(set) var showGenerics: Bool = true
    /// How extensions are visualized: as separate boxes, merged into the base type, or hidden.
    public var showExtensions: ExtensionVisualization?
    /// The glyph prefixed to members that were merged in from an extension (PlantUML OpenIconic markup).
    public private(set) var mergedExtensionMemberIndicator: String? = "<&bolt>"
    /// Whether each member is annotated with its access-level symbol (`+`, `-`, `#`, …).
    public private(set) var showMemberAccessLevelAttribute: Bool = true
    /// Name patterns to exclude from the diagram entirely.
    public private(set) var exclude: [String]?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let havingAccessLevel = try container.decodeIfPresent([AccessLevel].self, forKey: .havingAccessLevel) {
            self.havingAccessLevel = havingAccessLevel
        }
        if let showMembersWithAccessLevel = try container.decodeIfPresent(
            [AccessLevel].self, forKey: .showMembersWithAccessLevel
        ) {
            self.showMembersWithAccessLevel = showMembersWithAccessLevel
        }
        if let showNestedTypes = try container.decodeIfPresent(Bool.self, forKey: .showNestedTypes) {
            self.showNestedTypes = showNestedTypes
        }
        if let showGenerics = try container.decodeIfPresent(Bool.self, forKey: .showGenerics) {
            self.showGenerics = showGenerics
        }
        if let visualization = try? container.decodeIfPresent(String.self, forKey: .showExtensions) {
            showExtensions = ExtensionVisualization(rawValue: visualization)
        } else if let showExtensionsBoolean = try? container.decodeIfPresent(Bool.self, forKey: .showExtensions) {
            showExtensions = ExtensionVisualization.from(showExtensionsBoolean)
        }
        if let mergedExtensionMemberIndicator = try container.decodeIfPresent(
            String.self, forKey: .mergedExtensionMemberIndicator
        ) {
            self.mergedExtensionMemberIndicator = mergedExtensionMemberIndicator
        }
        if let showMemberAccessLevelAttribute = try container.decodeIfPresent(
            Bool.self, forKey: .showMemberAccessLevelAttribute
        ) {
            self.showMemberAccessLevelAttribute = showMemberAccessLevelAttribute
        }
        if let exclude = try container.decodeIfPresent([String].self, forKey: .exclude) {
            self.exclude = exclude
        }
    }

    public init(
        havingAccessLevel: [AccessLevel] = [.open, .public, .package, .internal, .private],
        showMembersWithAccessLevel: [AccessLevel] = [.open, .public, .package, .internal, .private],
        showNestedTypes: Bool = true,
        showGenerics: Bool = true,
        showExtensions: ExtensionVisualization? = nil,
        mergedExtensionMemberIndicator: String? = "<&bolt>",
        showMemberAccessLevelAttribute: Bool = true,
        exclude: [String]? = nil
    ) {
        self.havingAccessLevel = havingAccessLevel
        self.showMembersWithAccessLevel = showMembersWithAccessLevel
        self.showNestedTypes = showNestedTypes
        self.showGenerics = showGenerics
        self.showExtensions = showExtensions
        self.mergedExtensionMemberIndicator = mergedExtensionMemberIndicator
        self.showMemberAccessLevelAttribute = showMemberAccessLevelAttribute
        self.exclude = exclude
    }
}
