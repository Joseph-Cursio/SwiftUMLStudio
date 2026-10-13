import Foundation

/// Format-agnostic context accumulated while building a diagram from SyntaxStructures
class DiagramContext {
    private(set) var configuration: Configuration
    let format: DiagramFormat

    /// The element-rendering options, without the hop through `configuration`.
    ///
    /// Callers holding a context were reaching `context.configuration.elements.showGenerics` —
    /// three levels of knowledge about how a context stores its settings, for a value the context
    /// can hand over directly. `configuration` stays public for the callers that want the whole
    /// thing (`skip(element:basedOn:)` takes it entire).
    var elements: ElementOptions { configuration.elements }

    var uniqueNameForElement: [SyntaxStructure: String] = [:]

    var uniqElementNames: [String] = []
    var uniqElementAndTypes: [String: String] = [:]

    /// Every id an element may be declared under: the names of the elements the diagram will
    /// draw, plus each alias `uniqName` has issued. A suffixed alias must avoid all of them, or
    /// Mermaid and PlantUML declare two elements under one id.
    ///
    /// Kept apart from `uniqElementNames` on purpose. `addLinking` looks names up there by raw
    /// name, and a type literally named `Foo0` must still count as a first declaration.
    private(set) var takenIdentifiers: Set<String> = []
    private(set) var connections: [String] = []
    private(set) var extnConnections: [String] = []

    private var linkTypeInheritance: String {
        (format == .nomnoml || format == .svg) ? "-:>" : "<|--"
    }

    private var linkTypeRealize: String {
        (format == .nomnoml || format == .svg) ? "--:>" : "<|.."
    }

    private var linkTypeDependency: String {
        (format == .nomnoml || format == .svg) ? "-->" : "<.."
    }

    private var linkTypeGeneric: String {
        (format == .nomnoml || format == .svg) ? "-" : "--"
    }

    init(configuration: Configuration = .default) {
        self.configuration = configuration
        self.format = configuration.format
    }

    var index = 0

    func addLinking(item: SyntaxStructure, parent: SyntaxStructure) {
        var linkTo = parent.name?.removeAngleBracketsWithContent() ?? "___"

        if linkTo.starts(with: "@") {
            linkTo = "\"\(linkTo)\""
        }

        guard skipLinking(
            element: parent,
            basedOn: configuration.relationships.inheritance?.exclude
        ) == false else { return }
        guard let fullName = item.fullName else { return }
        let namedConnection = (uniqElementAndTypes[linkTo] != nil)
            ? "\(uniqElementAndTypes[linkTo] ?? "--ERROR--")"
            : "inherits"
        var linkTypeKey = fullName + "LinkType"

        if uniqElementAndTypes[linkTo] == "conforms to" {
            linkTypeKey = linkTo + "LinkType"
        }

        var connect: String
        let arrow = uniqElementAndTypes[linkTypeKey] ?? "--ERROR--"
        if format == .nomnoml || format == .svg {
            connect = "[\(fullName)] \(arrow) [\(linkTo)]"
        } else {
            connect = "\(linkTo) \(arrow) \(fullName)"
            if format == .plantuml, let relStyle = relationshipStyle(for: namedConnection)?.plantuml {
                connect += " \(relStyle)"
            }
        }
        if let relationshipLabel = relationshipLabel(for: namedConnection) {
            connect += " : \(relationshipLabel)"
        }
        connections.append(connect)
    }

    func skipLinking(element: SyntaxStructure, basedOn excludeElements: [String]?) -> Bool {
        element.isExcluded(byPatterns: excludeElements)
    }

    func relationshipLabel(for name: String) -> String? {
        if name == "inherits" {
            return configuration.relationships.inheritance?.label
        } else if name == "conforms to" {
            return configuration.relationships.realize?.label
        } else if name == "ext" {
            return configuration.relationships.dependency?.label
        } else {
            return nil
        }
    }

    func relationshipStyle(for name: String) -> RelationshipStyle? {
        if name == "inherits" {
            return configuration.relationships.inheritance?.style
        } else if name == "conforms to" {
            return configuration.relationships.realize?.style
        } else if name == "ext" {
            return configuration.relationships.dependency?.style
        } else {
            return nil
        }
    }

    /// Reserve the names of the elements the diagram is about to draw, before the first alias is
    /// issued. A first declaration keeps its own name as its alias, so a suffixed alias handed out
    /// earlier must not take a name that is only declared later — `struct Foo {}`,
    /// `extension Foo {}`, `extension Foo0 {}` would otherwise declare `Foo0` twice.
    func reserveIdentifiers(of items: [SyntaxStructure]) {
        takenIdentifiers.formUnion(items.compactMap(\.fullName))
    }

    func uniqName(item: SyntaxStructure, relationship: String) -> String {
        guard let name = item.fullName else { return "" }
        var newName = name
        let linkTypeKey = name + "LinkType"
        if uniqElementNames.contains(name) {
            // The counter is diagram-wide, so where no candidate is taken every alias is what
            // it always was; a taken candidate is skipped, never reused.
            repeat {
                newName = name + "\(index)"
                index += 1
            } while takenIdentifiers.contains(newName)
            let hasMatchingParent = uniqueNameForElement.keys
                .first(where: { $0.name == name && $0.kind != .extension }) != nil
            if item.kind == ElementKind.extension, hasMatchingParent {
                var connect: String
                if format == .nomnoml || format == .svg {
                    connect = "[\(newName)] \(linkTypeDependency) [\(name)]"
                } else {
                    connect = "\(name) \(linkTypeDependency) \(newName)"
                    if format == .plantuml, let relStyle = configuration.relationships.dependency?.style?.plantuml {
                        connect += " \(relStyle)"
                    }
                }
                connect += " : \(configuration.relationships.dependency?.label ?? relationship)"
                extnConnections.append(connect)
            }
        } else {
            uniqElementNames.append(name)
            uniqElementAndTypes[name] = relationship

            if relationship == "inherits" {
                uniqElementAndTypes[linkTypeKey] = linkTypeInheritance
            } else if relationship == "conforms to" {
                uniqElementAndTypes[linkTypeKey] = linkTypeRealize
            } else if relationship == "ext" {
                uniqElementAndTypes[linkTypeKey] = linkTypeDependency
            } else {
                uniqElementAndTypes[linkTypeKey] = linkTypeGeneric
            }
        }
        takenIdentifiers.insert(newName)
        uniqueNameForElement[item] = newName
        return newName
    }

    func collectNestedTypeConnections(items: [SyntaxStructure]) {
        guard format == .plantuml || format == .nomnoml || format == .svg else { return }
        for item in items where item.parent != nil {
            guard let name = uniqueNameForElement[item],
                  let parent = item.parent,
                  let parentName = uniqueNameForElement[parent] ?? parent.name
            else {
                continue
            }
            if format == .nomnoml || format == .svg {
                connections.append("[\(parentName)] +- [\(name)]")
            } else {
                connections.append("\(parentName) +-- \(name)")
            }
        }
    }
}
