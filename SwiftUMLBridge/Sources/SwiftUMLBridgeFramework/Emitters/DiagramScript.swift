import Foundation

/// Swift type representing a diagram script (PlantUML or Mermaid)
public struct DiagramScript: @unchecked Sendable {
    /// Textual representation of the script
    public private(set) var text: String = ""

    /// Output format for this script
    public let format: DiagramFormat

    /// Positioned layout graph (available when format is `.svg`).
    public private(set) var layoutGraph: LayoutGraph?

    private var context: DiagramContext

    /// Default initializer
    internal init(items: [SyntaxStructure], configuration: Configuration = .default) {
        format = configuration.format
        context = DiagramContext(configuration: configuration)

        let methodStart = Date()
        let definitions = buildDefinitions(from: items)

        switch format {
        case .plantuml:
            text = buildPlantUMLText(configuration: configuration, definitions: definitions)
        case .mermaid:
            text = buildMermaidText(configuration: configuration, definitions: definitions)
        case .nomnoml:
            text = buildNomnomlText(configuration: configuration, definitions: definitions)
        case .svg:
            text = buildSVGText(items: items, configuration: configuration)
        }

        BridgeLogger.shared.debug("DiagramScript created in \(Date().timeIntervalSince(methodStart)) seconds")
    }

    private func buildDefinitions(from items: [SyntaxStructure]) -> String {
        var adjustedItems = items

        if context.configuration.elements.showNestedTypes {
            adjustedItems = adjustedItems.populateNestedTypes()
        }

        adjustedItems = adjustedItems.orderedByProtocolsFirstExtensionsLast()

        if context.configuration.shallExtensionsBeMerged {
            let indicator = context.configuration.elements.mergedExtensionMemberIndicator
            adjustedItems = adjustedItems.mergeExtensions(mergedMemberIndicator: indicator)
        }

        let newLine = "\n"
        var mainContent = newLine

        for (index, element) in adjustedItems.enumerated() {
            if let elementText = processStructureItem(item: element, index: index) {
                mainContent.appendAsNewLine(elementText)
            }
        }

        context.collectNestedTypeConnections(items: adjustedItems)

        let connections = context.connections.joined(separator: newLine)
        let extnConnections = context.extnConnections.joined(separator: newLine)
        return mainContent + newLine + connections + newLine + extnConnections
    }

    private func buildPlantUMLText(configuration: Configuration, definitions: String) -> String {
        var result = "@startuml"
        if let theme = configuration.theme {
            result.appendAsNewLine("!theme \(theme.rawValue)")
        }
        if let includeRemoteURL = configuration.includeRemoteURL {
            result.appendAsNewLine("!include \(includeRemoteURL)")
        }
        result.appendAsNewLine(defaultStyling)
        result.appendAsNewLine("set namespaceSeparator none")
        if let texts = configuration.texts?.plantuml() {
            result.appendAsNewLine(texts)
        }
        result.appendAsNewLine(definitions)
        result.appendAsNewLine("@enduml")
        return result
    }

    private func buildMermaidText(configuration: Configuration, definitions: String) -> String {
        var result = "classDiagram"
        if let texts = configuration.texts {
            if let title = texts.title { result.appendAsNewLine("%% title: \(title)") }
            if let header = texts.header { result.appendAsNewLine("%% header: \(header)") }
            if let footer = texts.footer { result.appendAsNewLine("%% footer: \(footer)") }
        }
        result.appendAsNewLine(definitions)
        return result
    }

    private func buildNomnomlText(configuration: Configuration, definitions: String) -> String {
        var result = "#direction: down"
        // Output-building — nomnoml directive lines appended into a diagram script, not a registry.
        // swiftprojectlint:disable:next parallel-list-drift
        result.appendAsNewLine("#fontSize: 12")
        result.appendAsNewLine("#spacing: 60")
        result.appendAsNewLine("#padding: 10")
        result.appendAsNewLine("#edges: rounded")
        if let texts = configuration.texts {
            if let title = texts.title { result.appendAsNewLine("// title: \(title)") }
            if let footer = texts.footer { result.appendAsNewLine("// footer: \(footer)") }
        }
        result.appendAsNewLine(definitions)
        return result
    }

    /// Encode diagram text for PlantUML URL embedding
    public func encodeText() -> String {
        DiagramText(rawValue: text).encodedValue
    }

    /// Default styling block (PlantUML only; empty string for Mermaid)
    internal var defaultStyling: String {
        guard format == .plantuml else { return "" }
        let hideShowCommands: [String] = context.configuration.hideShowCommands ?? ["hide empty members"]
        let skinparamCommands: [String] = context.configuration.skinparamCommands ?? ["skinparam shadowing false"]

        if hideShowCommands.isEmpty, skinparamCommands.isEmpty {
            return ""
        } else {
            return """
            ' STYLE START
            \(hideShowCommands.joined(separator: "\n"))
            \(skinparamCommands.joined(separator: "\n"))
            ' STYLE END
            """
        }
    }

    func processStructureItem(item: SyntaxStructure, index _: Int) -> String? {
        let processableKinds: [ElementKind] = [.class, .struct, .extension, .enum, .protocol, .actor, .macro]
        guard let elementKind = item.kind else { return nil }
        guard processableKinds.contains(elementKind) else { return nil }
        switch format {
        case .plantuml:
            return item.plantuml(context: context) ?? nil
        case .mermaid:
            return item.mermaid(context: context) ?? nil
        case .nomnoml:
            return item.nomnoml(context: context) ?? nil
        case .svg:
            // SVG uses LayoutGraphBuilder directly; skip per-item text emission
            return nil
        }
    }

    private mutating func buildSVGText(items: [SyntaxStructure], configuration: Configuration) -> String {
        let graph = LayoutGraphBuilder.buildClassDiagram(from: items, configuration: configuration)
        let positioned = DagreLayoutEngine.layout(graph)
        layoutGraph = positioned
        return SVGRenderer.render(positioned)
    }
}
