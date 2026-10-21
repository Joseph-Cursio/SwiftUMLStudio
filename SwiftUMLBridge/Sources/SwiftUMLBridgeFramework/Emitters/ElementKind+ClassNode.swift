extension ElementKind {
    /// How the Mermaid and Nomnoml class-diagram emitters draw a type of this kind: the
    /// relationship its alias is made under (see `DiagramContext.uniqName`) and the stereotype it
    /// is labelled with. The two emitters each carried a copy of this table (#209); Nomnoml
    /// overrides only `protocol`, which it labels `interface`. `nil` for `.macro`, which each
    /// draws as a comment, and for the kinds no class diagram draws.
    ///
    /// The labels are the formats' own and are deliberately not read from
    /// `configuration.stereotypes`: those carry a PlantUML spot (a character and a colour) that
    /// neither format has syntax for. See `SyntaxStructure+PlantUML.plantUMLText(for:generics:context:)`.
    var classNode: (relationship: String, stereotype: String)? {
        switch self {
        case .class: return ("inherits", "class")
        case .struct: return ("inherits", "struct")
        case .extension: return ("ext", "extension")
        case .enum: return ("", "enum")
        case .protocol: return ("conforms to", "protocol")
        case .actor: return ("actor", "actor")
        default: return nil
        }
    }
}
