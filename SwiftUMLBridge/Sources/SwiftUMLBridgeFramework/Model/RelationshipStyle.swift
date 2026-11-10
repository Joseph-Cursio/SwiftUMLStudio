/// Inline style for a relation (linking or arrow)
public enum RelationshipInlineStyle: String, Codable, Sendable {
    case bold
    case dashed
    case dotted
    case hidden
    case plain
}

/// Style information for a relation and its label
public struct RelationshipStyle: Codable, Sendable {
    public private(set) var lineStyle: RelationshipInlineStyle = .plain
    public private(set) var lineColor: Color = .black
    public private(set) var textColor: Color = .black

    var plantuml: String {
        "#line:\(lineColor);line.\(lineStyle);text:\(textColor)"
    }
}
