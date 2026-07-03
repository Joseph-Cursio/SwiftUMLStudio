import Foundation

/// Access Level for Swift variables and methods
public enum AccessLevel: String, Codable, Sendable {
    case open
    case `public`
    case `package`
    case `internal`
    case `private`
    case `fileprivate`
}

/// Configuration options to influence the generation and visual representation of the class diagram
public struct Configuration: Codable, Sendable {
    public init(
        files: FileOptions = FileOptions(),
        elements: ElementOptions = ElementOptions(),
        hideShowCommands: [String]? = ["hide empty members"],
        skinparamCommands: [String]? = ["skinparam shadowing false"],
        includeRemoteURL: String? = nil,
        theme: Theme? = nil,
        relationships: RelationshipOptions = RelationshipOptions(),
        stereotypes: Stereotypes = Stereotypes.default,
        texts: PageTexts? = nil,
        format: DiagramFormat = .plantuml
    ) {
        self.files = files
        self.elements = elements
        self.hideShowCommands = hideShowCommands
        self.skinparamCommands = skinparamCommands
        self.includeRemoteURL = includeRemoteURL
        self.theme = theme
        self.relationships = relationships
        self.stereotypes = stereotypes
        self.texts = texts
        self.format = format
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let files = try container.decodeIfPresent(FileOptions.self, forKey: .files) {
            self.files = files
        }
        if let elements = try container.decodeIfPresent(ElementOptions.self, forKey: .elements) {
            self.elements = elements
        }
        if let hideShowCommands = try container.decodeIfPresent([String].self, forKey: .hideShowCommands) {
            self.hideShowCommands = hideShowCommands
        }
        if let skinparamCommands = try container.decodeIfPresent([String].self, forKey: .skinparamCommands) {
            self.skinparamCommands = skinparamCommands
        }
        if let includeRemoteURL = try container.decodeIfPresent(String.self, forKey: .includeRemoteURL) {
            self.includeRemoteURL = includeRemoteURL
        }
        if let theme = try container.decodeIfPresent(String.self, forKey: .theme) {
            self.theme = Theme.__directive__(theme)
        }
        if let relationships = try container.decodeIfPresent(RelationshipOptions.self, forKey: .relationships) {
            self.relationships = relationships
        }
        if let stereotypes = try container.decodeIfPresent(Stereotypes.self, forKey: .stereotypes) {
            self.stereotypes = stereotypes
        }
        if let texts = try container.decodeIfPresent(PageTexts.self, forKey: .texts) {
            self.texts = texts
        }
        if let format = try container.decodeIfPresent(DiagramFormat.self, forKey: .format) {
            self.format = format
        }
    }

    /// A configuration using the defaults for every option.
    public static let `default` = Configuration()

    /// Which source files are included in generation (globs and excludes).
    public var files = FileOptions()
    /// Which declarations and members are drawn, filtered by access level and more.
    public var elements = ElementOptions()
    /// PlantUML `hide`/`show` directives emitted verbatim (e.g. `hide empty members`).
    public private(set) var hideShowCommands: [String]? = ["hide empty members"]
    /// PlantUML `skinparam` directives emitted verbatim (e.g. `skinparam shadowing false`).
    public private(set) var skinparamCommands: [String]? = ["skinparam shadowing false"]
    /// A remote `!include` URL prepended to PlantUML output, for shared styling.
    public private(set) var includeRemoteURL: String?
    /// The PlantUML theme applied to the diagram, when set.
    public private(set) var theme: Theme?
    /// Which relationship edges (inheritance, conformance, dependency) are drawn and how they are labelled.
    public var relationships = RelationshipOptions()
    /// The per-kind stereotype spots (class, struct, enum, …) applied to type boxes.
    public private(set) var stereotypes = Stereotypes(
        classStereotype: Stereotype.class,
        structStereotype: Stereotype.struct,
        extensionStereotype: Stereotype.extension,
        enumStereotype: Stereotype.enum,
        protocolStereotype: Stereotype.protocol
    )
    /// Optional title, header, footer, and caption text for the page.
    public var texts: PageTexts?
    /// The emitted diagram syntax: PlantUML, Mermaid, or Nomnoml.
    public var format: DiagramFormat = .plantuml

    internal var shallExtensionsBeMerged: Bool {
        elements.showExtensions.safelyUnwrap == .merged
    }
}
