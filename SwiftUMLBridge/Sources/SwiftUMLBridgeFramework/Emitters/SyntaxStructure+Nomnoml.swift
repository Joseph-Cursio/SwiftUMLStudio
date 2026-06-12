import Foundation

extension SyntaxStructure {
    /// Textual representation of this element in nomnoml syntax
    func nomnoml(context: DiagramContext) -> String? {
        renderDiagramText(context: context) { kind, generics, context in
            nomnomlText(for: kind, generics: generics, context: context)
        }
    }

    private func nomnomlText(
        for kind: ElementKind,
        generics: String?,
        context: DiagramContext
    ) -> String? {
        switch kind {
        case ElementKind.class:
            return nomnomlNode(relationship: "inherits", stereotype: "class", generics: generics, context: context)
        case ElementKind.struct:
            return nomnomlNode(relationship: "inherits", stereotype: "struct", generics: generics, context: context)
        case ElementKind.extension:
            return nomnomlNode(relationship: "ext", stereotype: "extension", generics: generics, context: context)
        case ElementKind.enum:
            return nomnomlNode(relationship: "", stereotype: "enum", generics: generics, context: context)
        case ElementKind.protocol:
            return nomnomlNode(
                relationship: "conforms to", stereotype: "interface", generics: generics, context: context
            )
        case ElementKind.actor:
            return nomnomlNode(relationship: "actor", stereotype: "actor", generics: generics, context: context)
        case ElementKind.macro:
            let macroName = context.uniqName(item: self, relationship: "macro")
            return "// macro: \(displayName ?? "unknown") (\(macroName))"
        default:
            BridgeLogger.shared.error("element kind not supported for nomnoml rendering: \(kind.rawValue)")
            return nil
        }
    }

    /// Build a nomnoml node declaration: [<stereotype> Name|properties|methods]
    private func nomnomlNode(
        relationship: String,
        stereotype: String,
        generics: String?,
        context: DiagramContext
    ) -> String {
        let alias = context.uniqName(item: self, relationship: relationship)
        let typeName = displayName ?? name ?? "unknown"
        let genericsStr = generics.map { " \($0)" } ?? ""

        let macroAnnotations = attributeNames.isEmpty ? "" : " <<\(attributeNames.joined(separator: ", "))>>"
        let moduleAnnotation = module.map { " <<\($0)>>" } ?? ""
        let headerText = "\(typeName)\(genericsStr)\(macroAnnotations)\(moduleAnnotation)"

        let (properties, methods) = nomnomlMembers(context: context)

        // nomnoml uses alias for connections, but display name for rendering
        // Format: [<stereotype> alias_DisplayName|properties|methods]
        var sections = "<\(stereotype)> \(headerText)"
        if !properties.isEmpty {
            sections += "|\(properties.joined(separator: ";"))"
        }
        if !methods.isEmpty {
            sections += "|\(methods.joined(separator: ";"))"
        }

        // Store mapping from alias to display for connections
        return "[\(sections)]"
    }

    private func nomnomlMembers(context: DiagramContext) -> (properties: [String], methods: [String]) {
        var properties: [String] = []
        var methods: [String] = []
        guard let substructure, !substructure.isEmpty else { return (properties, methods) }

        for sub in substructure {
            guard let member = nomnomlMember(element: sub, context: context) else { continue }
            switch member.category {
            case .property:
                properties.append(member.text)
            case .method:
                methods.append(member.text)
            }
        }
        return (properties, methods)
    }

    private func nomnomlMember(
        element: SyntaxStructure,
        context: DiagramContext
    ) -> (text: String, category: NomnomlMemberCategory)? {
        guard let actualElement = renderableMember(from: element, context: context) else { return nil }

        var prefix = ""
        if context.configuration.elements.showMemberAccessLevelAttribute {
            prefix = nomnomlAccessPrefix(for: actualElement)
        }

        return nomnomlMemberText(element: actualElement, prefix: prefix)
    }

    private func nomnomlAccessPrefix(for element: SyntaxStructure) -> String {
        guard let accessibility = element.accessibility else { return "~" }
        switch accessibility {
        case .open, .public:
            return "+"
        case .internal, .package, .other:
            return "~"
        case .private, .fileprivate:
            return "-"
        }
    }

    private func nomnomlMemberText(
        element: SyntaxStructure,
        prefix: String
    ) -> (text: String, category: NomnomlMemberCategory)? {
        guard let kind = element.kind, let name = element.name else { return nil }
        // Escape nomnoml-reserved characters in names
        let safeName = name.nomnomlEscaped
        switch kind {
        case .functionMethodInstance:
            return ("\(prefix)\(safeName)()", .method)
        case .functionMethodStatic:
            return ("\(prefix)static \(safeName)()", .method)
        case .varInstance:
            if let typename = element.typename {
                return ("\(prefix)\(safeName): \(typename.nomnomlEscaped)", .property)
            }
            return ("\(prefix)\(safeName)", .property)
        case .varStatic:
            if let typename = element.typename {
                return ("\(prefix)static \(safeName): \(typename.nomnomlEscaped)", .property)
            }
            return ("\(prefix)static \(safeName)", .property)
        case .enumelement:
            return ("\(safeName)", .property)
        default:
            return nil
        }
    }
}

private enum NomnomlMemberCategory {
    case property
    case method
}
