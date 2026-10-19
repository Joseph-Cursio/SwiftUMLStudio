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
    /// The arrow for each element's supertype edges, from the relationship `uniqName` named it with,
    /// kept per element rather than under `<name>LinkType` in `uniqElementAndTypes`, where a repeat
    /// read its name's first declaration's arrow and a type named `PLinkType` overwrote protocol
    /// `P`'s. `addLinking` draws an edge to a protocol the sources declare, drawn or hidden, with
    /// the realization arrow instead.
    private var linkTypeForElement: [SyntaxStructure: String] = [:]

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
    /// Where the edge of each drawn nested type ends when the diagram does not draw its parent,
    /// found by `reserveIdentifiers(drawing:among:)`; a nested type missing here gets no edge.
    private var hiddenParentEnds: [ObjectIdentifier: HiddenParentEnd] = [:]
    /// The drawn type each drawn extension extends, where its `ext` edge ends, found by
    /// `reserveIdentifiers(drawing:among:)`; an extension missing here gets no edge.
    private var extendedTypes: [ObjectIdentifier: SyntaxStructure] = [:]
    /// Where supertype edges end, found as SVG finds them, set by
    /// `reserveIdentifiers(drawing:among:)`.
    private var edgeEnds: DrawnEdgeEnds?
    /// The supertype edges `addLinking` has drawn. `connections` writes them out once every
    /// element has its alias: the element an edge ends on may be drawn after the one it starts at.
    private var supertypeEdges: [SupertypeEdge] = []
    /// Each box's supertype edge ends so far, so a second edge from a box to the same end is
    /// left out, as SVG leaves it out (#76).
    private var supertypeEndsDrawn: Set<SupertypeEndKey> = []
    /// The edges from nested types to their parents, `collectNestedTypeConnections(items:)` drew.
    private var nestingConnections: [String] = []
    /// Each supertype edge as the format writes it, in the order `addLinking` drew them, then
    /// each nesting edge.
    var connections: [String] {
        let declared = Set(uniqueNameForElement.compactMap { declaresIdentifier(of: $0.key) ? $0.value : nil })
        return supertypeEdges.compactMap { text(of: $0, besides: declared) } + nestingConnections
    }
    private(set) var extnConnections: [String] = []
    /// The typealiases among the items the diagram was built from, found by
    /// `reserveIdentifiers(drawing:among:)`: a supertype written through one ends on the type it
    /// aliases (#125).
    private var aliases = TypeAliasResolver.none

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

    /// The name `addLinking` writes for `parent`'s end of an edge, written in `scope`, when the
    /// edge ends on no drawn element (`supertypeEnd(for:from:)`), or `nil` when
    /// `relationships.inheritance.exclude` or `relationships.realize.exclude` suppresses the
    /// edge. Both drawing and `reserveIdentifiers(drawing:)` go through here, so an excluded
    /// target is neither drawn nor reserved. A name written through a typealias is the aliased
    /// type's, so `struct S: Q` after `typealias Q = Proto` reads as `struct S: Proto` (#125).
    func linkTarget(for parent: SyntaxStructure, from scope: DeclarationScope) -> String? {
        let excluded = configuration.relationships.supertypeExcludePatterns
        guard aliases.isExcluded(parent, from: scope, byPatterns: excluded) == false else { return nil }
        let linkTo = parent.name.map { aliases.resolve($0.removeAngleBracketsWithContent(), from: scope) } ?? "___"
        return linkTo.starts(with: "@") ? "\"\(linkTo)\"" : linkTo
    }

    /// Where the edge to `parent`, written in `scope`, ends, as SVG ends it (`DrawnEdgeEnds`): the
    /// drawn element the name means there, by file, module and access, or a hidden type's
    /// stand-in. Writing the name instead ended the edge on the first box with that name, so
    /// `struct U: P` reached another file's `P`. `element` is `nil` when SVG finds none: a type
    /// outside the diagram, such as `Codable`, or a hidden type with no stand-in. `isProtocol`
    /// says whether the edge is a realization (`DrawnEdgeEnds.supertype(named:from:)`).
    private func supertypeEnd(
        for parent: SyntaxStructure, from scope: DeclarationScope
    ) -> (element: SyntaxStructure?, isProtocol: Bool) {
        guard let name = parent.name?.removeAngleBracketsWithContent(), let edgeEnds else { return (nil, false) }
        return edgeEnds.supertype(named: name, from: scope)
    }

    /// Draws the edge from `item` to its supertype `parent`. It starts at the alias `uniqName` gave
    /// `item`, so a second declaration of a name, such as an extension or the other branch of an
    /// `#if`, draws its supertypes from its own box (#68). It ends on the drawn element
    /// `supertypeEnd(for:from:)` finds, under the alias `uniqName` gives that element. With none,
    /// it is written to `linkTarget(for:from:)`, a node of its own, unless a drawn element
    /// declares that name: then it is left out, as SVG leaves it out, rather than ending on that
    /// unrelated box (`connections`). An edge from `item`'s box that ends where one before it
    /// does, as a conformance two `#if` clauses or a merged extension repeat, is left out too.
    ///
    /// The edge is named after the type `parent`'s name means, drawn or hidden, whichever box it
    /// ends on: `conforms to` for a protocol, and `inherits` for anything else, a class, an enum's
    /// raw type, or a type outside the diagram such as `Codable`, whose kind the diagram does not
    /// know. Named `conforms to`, it takes the realization arrow and that label and style;
    /// otherwise the arrow of `item`'s own kind. A context that never resolved its ends
    /// (`reserveIdentifiers(drawing:among:)`) names an edge as the name's first box drawn so far.
    /// `scope` is where `parent`'s name is written, `item`'s own scope by default: a merged
    /// extension's scope for a supertype it carried.
    func addLinking(item: SyntaxStructure, parent: SyntaxStructure, from scope: DeclarationScope? = nil) {
        let scope = scope ?? DeclarationScope(of: item)
        guard let linkTo = linkTarget(for: parent, from: scope) else { return }
        guard let fullName = item.fullName else { return }
        let (end, isProtocol) = supertypeEnd(for: parent, from: scope)
        let key = SupertypeEndKey(child: ObjectIdentifier(item), end: end.map(ObjectIdentifier.init), written: linkTo)
        guard supertypeEndsDrawn.insert(key).inserted else { return }
        let namedConnection = edgeEnds == nil
            ? uniqElementAndTypes[linkTo] ?? "inherits"
            : isProtocol ? "conforms to" : "inherits"
        let arrow = namedConnection == "conforms to"
            ? linkTypeRealize
            : linkTypeForElement[item] ?? "--ERROR--"
        supertypeEdges.append(SupertypeEdge(
            child: uniqueNameForElement[item] ?? fullName, arrow: arrow,
            label: relationshipLabel(for: namedConnection),
            plantUMLStyle: format == .plantuml ? relationshipStyle(for: namedConnection)?.plantuml : nil,
            end: end, written: linkTo
        ))
    }

    /// A supertype edge as `addLinking` works it out: everything but the id of its end, which
    /// waits for `end`'s alias.
    private struct SupertypeEdge {
        let child: String
        let arrow: String
        let label: String?
        let plantUMLStyle: String?
        /// The drawn element the edge ends on, or `nil` to end it on `written`.
        let end: SyntaxStructure?
        let written: String
    }

    /// Where a supertype edge from a box ends: on a drawn element, or on the name it is written to.
    private struct SupertypeEndKey: Hashable {
        let child: ObjectIdentifier
        let end: ObjectIdentifier?
        let written: String

        init(child: ObjectIdentifier, end: ObjectIdentifier?, written: String) {
            self.child = child
            self.end = end
            // An edge to a drawn element ends there however its name is written.
            self.written = end == nil ? written : ""
        }
    }

    /// `edge` as the format writes it. `nil` when SVG finds no drawn end for it and the name it
    /// would be written to is one of the `declared` ids, which would end it on that unrelated
    /// element, as `HiddenParentEnd` keeps a nesting edge from doing (#67). A context that never
    /// resolved its ends (`reserveIdentifiers(drawing:among:)`) writes every edge.
    private func text(of edge: SupertypeEdge, besides declared: Set<String>) -> String? {
        if edge.end == nil, edgeEnds != nil, declared.contains(edge.written) { return nil }
        let end = edge.end.flatMap { uniqueNameForElement[$0] } ?? edge.written
        if format == .nomnoml || format == .svg {
            return nomnomlEdge(from: edge.child, edge.arrow, to: end, label: edge.label)
        }
        var connect = "\(end) \(edge.arrow) \(edge.child)"
        if let style = edge.plantUMLStyle {
            connect += " \(style)"
        }
        if let label = edge.label {
            connect += " : \(label)"
        }
        return connect
    }

    /// A Nomnoml edge, `[start] arrow label [end]`. nomnoml reads a label only beside the arrow;
    /// after the end, where Mermaid and PlantUML take it, it fails the whole diagram (#69). Each
    /// end is written as the id `SyntaxStructure.nomnoml(context:)` declares under, so it names
    /// that node.
    ///
    /// The label runs to the next `[`, so brackets become parentheses. nomnoml drops a line that
    /// starts with `//` and reads one that starts with `#` as a directive before it parses the
    /// rest, so a line break becomes a space.
    private func nomnomlEdge(from start: String, _ arrow: String, to end: String, label: String? = nil) -> String {
        let text = label?.split(whereSeparator: \.isNewline).joined(separator: " ")
            .replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
        let labelText = text.flatMap { $0.isEmpty ? nil : " \($0)" } ?? ""
        return "[\(start.nomnomlIdentifier)] \(arrow)\(labelText) [\(end.nomnomlIdentifier)]"
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
    /// elements it draws, and the names its edges give elements it does not draw — a supertype
    /// that ends on no drawn element, such as a conformance to `Codable` or a raw type, and a
    /// hidden parent of a drawn nested type. Mermaid and
    /// PlantUML give an edge's undeclared end a node of its own, so a suffix that took one of
    /// those names would join two elements. A first declaration keeps its own name as its alias,
    /// so a suffix must not take a name declared only later either: `struct Foo {}`,
    /// `extension Foo {}`, `extension Foo0 {}` would otherwise declare `Foo0` twice.
    ///
    /// `items` must be exactly the elements the diagram draws, and `prepared` every item it was
    /// built from, drawn or not (`items` when nil): the type an extension extends and a hidden
    /// parent's edge end are found among them (`DrawnEdgeEnds`). A hidden element's name that
    /// nothing in the diagram uses must not shift an alias.
    func reserveIdentifiers(drawing items: [SyntaxStructure], among prepared: [SyntaxStructure]? = nil) {
        let edgeEnds = DrawnEdgeEnds(drawing: Set(items), among: prepared ?? items)
        self.edgeEnds = edgeEnds
        aliases = TypeAliasResolver(flattened: prepared ?? items)
        if drawsNestedTypeConnections {
            hiddenParentEnds = HiddenParentEnd.ends(
                of: items, through: edgeEnds, declaringIdentifier: declaresIdentifier(of:)
            )
        }
        for item in items where item.kind == .extension {
            extendedTypes[ObjectIdentifier(item)] = edgeEnds.extendedType(of: item)
        }
        for item in items {
            if declaresIdentifier(of: item), let fullName = item.fullName {
                takenIdentifiers.insert(fullName)
            }
            // An edge that ends on a drawn element writes that element's alias, which `uniqName` takes.
            takenIdentifiers.formUnion(item.linkParents().compactMap { parent in
                let name = parent.supertype.name?.removeAngleBracketsWithContent()
                let end = name.flatMap { edgeEnds.element(at: .named($0, from: parent.scope)) }
                return end == nil ? linkTarget(for: parent.supertype, from: parent.scope) : nil
            })
            if case .undeclared(let parentName)? = hiddenParentEnds[ObjectIdentifier(item)] {
                takenIdentifiers.insert(parentName)
            }
        }
    }

    func uniqName(item: SyntaxStructure, relationship: String) -> String {
        guard let name = item.fullName else { return "" }
        var newName = name
        if uniqElementNames.contains(name) {
            // The counter is diagram-wide, so where no candidate is taken every alias is what
            // it always was; a taken candidate is skipped, never reused.
            repeat {
                newName = name + "\(index)"
                index += 1
            } while takenIdentifiers.contains(newName)
        } else {
            uniqElementNames.append(name)
            uniqElementAndTypes[name] = relationship
        }
        if item.kind == .extension {
            addExtensionEdge(from: item, alias: newName, relationship: relationship)
        }
        if declaresIdentifier(of: item) {
            takenIdentifiers.insert(newName)
        }
        uniqueNameForElement[item] = newName
        linkTypeForElement[item] = linkType(for: relationship)
        return newName
    }

    /// The arrow for the supertype edges of an element named with `relationship`, unless the
    /// supertype is a protocol the sources declare.
    private func linkType(for relationship: String) -> String {
        switch relationship {
        case "inherits": linkTypeInheritance
        case "conforms to": linkTypeRealize
        case "ext": linkTypeDependency
        default: linkTypeGeneric
        }
    }

    /// Draws the `ext` edge from extension `item`, declared as `alias`, to the type it extends:
    /// the drawn type its name means where it is written, the box `--merge-extensions` would merge
    /// it into (#107). Matching its name against the types drawn instead gave `extension
    /// Outer.Inner` no edge, and gave a second `extension Foo` one to the first when a nested
    /// `Bar.Foo` was drawn (#72). An extension of a hidden type, or of one outside the diagram,
    /// gets no edge.
    private func addExtensionEdge(from item: SyntaxStructure, alias: String, relationship: String) {
        // `dependency.exclude` hides only this edge (#113): the extension keeps its box, its
        // alias and its own conformances, so no id moves.
        guard let type = extendedTypes[ObjectIdentifier(item)], let typeAlias = uniqueNameForElement[type],
              drawsExtensionEdge(for: item) else { return }
        let label = configuration.relationships.dependency?.label ?? relationship
        if format == .nomnoml || format == .svg {
            extnConnections.append(nomnomlEdge(from: alias, linkTypeDependency, to: typeAlias, label: label))
            return
        }
        var connect = "\(typeAlias) \(linkTypeDependency) \(alias)"
        if format == .plantuml, let relStyle = configuration.relationships.dependency?.style?.plantuml {
            connect += " \(relStyle)"
        }
        extnConnections.append(connect + " : \(label)")
    }

    /// Draws an edge from each drawn nested type to its parent's alias. For a parent the diagram
    /// does not draw, the edge ends where `reserveIdentifiers(drawing:among:)` found SVG ends it,
    /// on a drawn stand-in or on the parent's qualified name, never on its short name, which
    /// could be the id of a drawn, unrelated type (#67), nor on an id a drawn element declares.
    func collectNestedTypeConnections(items: [SyntaxStructure]) {
        guard drawsNestedTypeConnections else { return }
        for item in items where item.parent != nil {
            guard let name = uniqueNameForElement[item],
                  let parent = item.nestingParent,
                  let parentName = uniqueNameForElement[parent] ?? hiddenParentName(of: item)
            else {
                continue
            }
            if format == .nomnoml || format == .svg {
                nestingConnections.append(nomnomlEdge(from: parentName, "+-", to: name))
            } else {
                nestingConnections.append("\(parentName) +-- \(name)")
            }
        }
    }

    /// The id the edge of `item` ends on when the diagram does not draw its parent, or nil when
    /// it has no edge.
    private func hiddenParentName(of item: SyntaxStructure) -> String? {
        switch hiddenParentEnds[ObjectIdentifier(item)] {
        case .element(let element)?: return uniqueNameForElement[element]
        case .undeclared(let name)?: return name
        case nil: return nil
        }
    }
}
