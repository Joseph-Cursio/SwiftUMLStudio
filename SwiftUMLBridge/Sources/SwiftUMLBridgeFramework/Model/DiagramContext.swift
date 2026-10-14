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

    /// Every id the diagram uses: the ids `reserveIdentifiers(drawing:)` found in it, plus each
    /// alias `uniqName` has issued. A suffixed alias must avoid all of them, or Mermaid and
    /// PlantUML draw two elements as one.
    ///
    /// Kept apart from `uniqElementNames` and `uniqElementAndTypes` on purpose: `uniqName` decides
    /// a first declaration by `uniqElementNames`, and `addLinking` reads `uniqElementAndTypes` by
    /// raw name, so a type literally named `Foo0` must still count as a first declaration.
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

    /// The id `addLinking` writes for `parent`'s end of an edge, or `nil` when
    /// `relationships.inheritance.exclude` or `relationships.realize.exclude` suppresses the
    /// edge. Both drawing and `reserveIdentifiers(drawing:)` go through here, so an excluded
    /// target is neither drawn nor reserved.
    func linkTarget(for parent: SyntaxStructure) -> String? {
        guard skipLinking(
            element: parent,
            basedOn: configuration.relationships.supertypeExcludePatterns
        ) == false else { return nil }
        let linkTo = parent.name?.removeAngleBracketsWithContent() ?? "___"
        return linkTo.starts(with: "@") ? "\"\(linkTo)\"" : linkTo
    }

    func addLinking(item: SyntaxStructure, parent: SyntaxStructure) {
        guard let linkTo = linkTarget(for: parent) else { return }
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

    /// Whether the edge from extension `item` to the type it extends is drawn: not when the
    /// extended type's name, which is the extension's own, matches `relationships.dependency.exclude`.
    private func drawsExtensionEdge(for item: SyntaxStructure) -> Bool {
        item.isExcluded(byPatterns: configuration.relationships.dependency?.exclude) == false
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

    /// Whether this format draws an edge from each nested type to its parent.
    private var drawsNestedTypeConnections: Bool {
        format == .plantuml || format == .nomnoml || format == .svg
    }

    /// Whether this format declares `item` under its alias. Mermaid and Nomnoml write a macro
    /// only as a comment, so there a macro's name is no id and must not shift one.
    private func declaresIdentifier(of item: SyntaxStructure) -> Bool {
        item.kind != .macro || format == .plantuml
    }

    /// Reserve every id the diagram will use, before the first alias is issued: the names of the
    /// elements it draws, and the names its edges give elements it does not draw — a supertype,
    /// a conformance or raw type, and a hidden parent of a drawn nested type. Mermaid and
    /// PlantUML give an edge's undeclared end a node of its own, so a suffix that took one of
    /// those names would join two elements. A first declaration keeps its own name as its alias,
    /// so a suffix must not take a name declared only later either: `struct Foo {}`,
    /// `extension Foo {}`, `extension Foo0 {}` would otherwise declare `Foo0` twice.
    ///
    /// `items` must be exactly the elements the diagram draws. A hidden element's name that
    /// nothing in the diagram uses must not shift an alias.
    func reserveIdentifiers(drawing items: [SyntaxStructure]) {
        let drawn = Set(items)
        for item in items {
            if declaresIdentifier(of: item), let fullName = item.fullName {
                takenIdentifiers.insert(fullName)
            }
            takenIdentifiers.formUnion(item.linkParents().compactMap(linkTarget(for:)))
            // `collectNestedTypeConnections` falls back to the qualified name of a parent it did not draw.
            if drawsNestedTypeConnections, let parent = item.nestingParent, !drawn.contains(parent),
               let parentName = parent.fullName {
                takenIdentifiers.insert(parentName)
            }
        }
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
            // `dependency.exclude` hides only this edge (#113): the extension keeps its box, its
            // alias and its own conformances, so no id moves.
            if item.kind == ElementKind.extension, hasMatchingParent, drawsExtensionEdge(for: item) {
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
        if declaresIdentifier(of: item) {
            takenIdentifiers.insert(newName)
        }
        uniqueNameForElement[item] = newName
        return newName
    }

    /// Draws an edge from each drawn nested type to its parent's alias or, for a parent the diagram
    /// does not draw, its qualified name. Its short name could be the id of a drawn, unrelated type
    /// (#67). An extension is only declared at file scope, so an undrawn extension parent's
    /// qualified name is the full name of the type it extends.
    func collectNestedTypeConnections(items: [SyntaxStructure]) {
        guard drawsNestedTypeConnections else { return }
        for item in items where item.parent != nil {
            guard let name = uniqueNameForElement[item],
                  let parent = item.nestingParent,
                  let parentName = uniqueNameForElement[parent] ?? parent.fullName
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
