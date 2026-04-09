import Testing
@testable import SwiftUMLBridgeFramework

@Suite("DiagramContext")
struct DiagramContextTests {

    // MARK: - uniqName

    @Test("uniqName registers name on first call")
    func uniqNameFirstCall() {
        let ctx = DiagramContext()
        let item = SyntaxStructure(kind: .class, name: "MyClass")
        let result = ctx.uniqName(item: item, relationship: "inherits")
        #expect(result == "MyClass")
        #expect(ctx.uniqElementNames.contains("MyClass"))
    }

    @Test("uniqName returns empty string when item has no name")
    func uniqNameNoName() {
        let ctx = DiagramContext()
        let item = SyntaxStructure(kind: .class)
        let result = ctx.uniqName(item: item, relationship: "inherits")
        #expect(result == "")
    }

    @Test("uniqName appends index on duplicate name")
    func uniqNameDuplicate() {
        let ctx = DiagramContext()
        let item1 = SyntaxStructure(kind: .class, name: "Foo")
        let item2 = SyntaxStructure(kind: .extension, name: "Foo")
        _ = ctx.uniqName(item: item1, relationship: "inherits")
        let result = ctx.uniqName(item: item2, relationship: "ext")
        #expect(result == "Foo0")
    }

    @Test("uniqName sets inheritance link type")
    func uniqNameInheritanceLinkType() {
        let ctx = DiagramContext()
        let item = SyntaxStructure(kind: .class, name: "Child")
        _ = ctx.uniqName(item: item, relationship: "inherits")
        #expect(ctx.uniqElementAndTypes["ChildLinkType"] == "<|--")
    }

    @Test("uniqName sets conforms-to link type")
    func uniqNameConformsToLinkType() {
        let ctx = DiagramContext()
        let item = SyntaxStructure(kind: .protocol, name: "MyProtocol")
        _ = ctx.uniqName(item: item, relationship: "conforms to")
        #expect(ctx.uniqElementAndTypes["MyProtocolLinkType"] == "<|..")
    }

    @Test("uniqName sets ext link type")
    func uniqNameExtLinkType() {
        let ctx = DiagramContext()
        let item = SyntaxStructure(kind: .extension, name: "MyExt")
        _ = ctx.uniqName(item: item, relationship: "ext")
        #expect(ctx.uniqElementAndTypes["MyExtLinkType"] == "<..")
    }

    @Test("uniqName sets generic link type for unknown relationship")
    func uniqNameGenericLinkType() {
        let ctx = DiagramContext()
        let item = SyntaxStructure(kind: .actor, name: "Actor")
        _ = ctx.uniqName(item: item, relationship: "actor")
        #expect(ctx.uniqElementAndTypes["ActorLinkType"] == "--")
    }

    @Test("uniqName extension with matching parent adds extnConnection")
    func uniqNameExtensionWithParent() {
        let ctx = DiagramContext()
        let parent = SyntaxStructure(kind: .class, name: "Foo")
        let ext_ = SyntaxStructure(kind: .extension, name: "Foo")
        _ = ctx.uniqName(item: parent, relationship: "inherits")
        _ = ctx.uniqName(item: ext_, relationship: "ext")
        #expect(ctx.extnConnections.isEmpty == false)
        #expect(ctx.extnConnections.first?.contains("Foo") == true)
    }

    // MARK: - relationshipLabel

    @Test("relationshipLabel returns inheritance label for 'inherits'")
    func relationshipLabelInherits() {
        let ctx = DiagramContext()
        #expect(ctx.relationshipLabel(for: "inherits") == "inherits")
    }

    @Test("relationshipLabel returns realize label for 'conforms to'")
    func relationshipLabelConformsTo() {
        let ctx = DiagramContext()
        #expect(ctx.relationshipLabel(for: "conforms to") == "conforms to")
    }

    @Test("relationshipLabel returns dependency label for 'ext'")
    func relationshipLabelExt() {
        let ctx = DiagramContext()
        #expect(ctx.relationshipLabel(for: "ext") == "ext")
    }

    @Test("relationshipLabel returns nil for unknown name")
    func relationshipLabelUnknown() {
        let ctx = DiagramContext()
        #expect(ctx.relationshipLabel(for: "unknown") == nil)
    }

    // MARK: - relationshipStyle

    @Test("relationshipStyle returns nil for 'inherits' when no style set")
    func relationshipStyleInheritsNoStyle() {
        let ctx = DiagramContext()
        #expect(ctx.relationshipStyle(for: "inherits") == nil)
    }

    @Test("relationshipStyle returns nil for 'conforms to' when no style set")
    func relationshipStyleConformsToNoStyle() {
        let ctx = DiagramContext()
        #expect(ctx.relationshipStyle(for: "conforms to") == nil)
    }

    @Test("relationshipStyle returns nil for 'ext' when no style set")
    func relationshipStyleExtNoStyle() {
        let ctx = DiagramContext()
        #expect(ctx.relationshipStyle(for: "ext") == nil)
    }

    @Test("relationshipStyle returns nil for unknown name")
    func relationshipStyleUnknown() {
        let ctx = DiagramContext()
        #expect(ctx.relationshipStyle(for: "actor") == nil)
    }

    // MARK: - addLinking

    @Test("addLinking appends connection for inheritance")
    func addLinkingInheritance() {
        let ctx = DiagramContext()
        let child = SyntaxStructure(kind: .class, name: "Child")
        let parent = SyntaxStructure(kind: .class, name: "Parent")
        _ = ctx.uniqName(item: child, relationship: "inherits")
        ctx.addLinking(item: child, parent: parent)
        #expect(ctx.connections.isEmpty == false)
        let conn = ctx.connections.first ?? ""
        #expect(conn.contains("Parent"))
        #expect(conn.contains("Child"))
    }

    @Test("addLinking wraps @-prefixed parent name in quotes")
    func addLinkingAtSignParent() {
        let ctx = DiagramContext()
        let child = SyntaxStructure(kind: .class, name: "MyClass")
        let parent = SyntaxStructure(kind: .protocol, name: "@Sendable")
        _ = ctx.uniqName(item: child, relationship: "inherits")
        ctx.addLinking(item: child, parent: parent)
        let conn = ctx.connections.first ?? ""
        #expect(conn.contains("\"@Sendable\""))
    }

    @Test("addLinking skips excluded parent")
    func addLinkingSkipsExcluded() {
        var config = Configuration.default
        config.relationships.inheritance = Relationship(label: "inherits", style: nil, exclude: ["Codable"])
        let ctx = DiagramContext(configuration: config)
        let child = SyntaxStructure(kind: .class, name: "MyType")
        let parent = SyntaxStructure(kind: .protocol, name: "Codable")
        _ = ctx.uniqName(item: child, relationship: "inherits")
        ctx.addLinking(item: child, parent: parent)
        #expect(ctx.connections.isEmpty)
    }

    @Test("addLinking removes angle brackets from parent name")
    func addLinkingRemovesGenericsFromParent() {
        let ctx = DiagramContext()
        let child = SyntaxStructure(kind: .class, name: "List")
        let parent = SyntaxStructure(kind: .protocol, name: "Collection<Element>")
        _ = ctx.uniqName(item: child, relationship: "inherits")
        ctx.addLinking(item: child, parent: parent)
        let conn = ctx.connections.first ?? ""
        #expect(conn.contains("Collection"))
        #expect(conn.contains("<Element>") == false)
    }

    // MARK: - collectNestedTypeConnections

    @Test("collectNestedTypeConnections adds parent-child connector")
    func collectNestedTypeConnections() {
        let ctx = DiagramContext()
        let parent = SyntaxStructure(kind: .class, name: "Outer")
        let child = SyntaxStructure(kind: .struct, name: "Inner")
        child.parent = parent
        _ = ctx.uniqName(item: parent, relationship: "inherits")
        _ = ctx.uniqName(item: child, relationship: "inherits")
        ctx.collectNestedTypeConnections(items: [parent, child])
        #expect(ctx.connections.isEmpty == false)
        let conn = ctx.connections.first ?? ""
        #expect(conn.contains("+--"))
        #expect(conn.contains("Outer"))
        #expect(conn.contains("Inner"))
    }

    @Test("collectNestedTypeConnections skips items with no parent")
    func collectNestedTypeConnectionsNoParent() {
        let ctx = DiagramContext()
        let item = SyntaxStructure(kind: .class, name: "TopLevel")
        _ = ctx.uniqName(item: item, relationship: "inherits")
        ctx.collectNestedTypeConnections(items: [item])
        #expect(ctx.connections.isEmpty)
    }

    @Test("collectNestedTypeConnections uses +- connector for nomnoml format")
    func collectNestedTypeConnectionsNomnoml() {
        let config = Configuration(format: .nomnoml)
        let ctx = DiagramContext(configuration: config)
        let parent = SyntaxStructure(kind: .class, name: "Outer")
        let child = SyntaxStructure(kind: .struct, name: "Inner")
        child.parent = parent
        _ = ctx.uniqName(item: parent, relationship: "inherits")
        _ = ctx.uniqName(item: child, relationship: "inherits")
        ctx.collectNestedTypeConnections(items: [parent, child])
        #expect(ctx.connections.isEmpty == false)
        let conn = ctx.connections.first ?? ""
        #expect(conn.contains("+-"))
        #expect(conn.contains("Outer"))
        #expect(conn.contains("Inner"))
    }

    // MARK: - Relationship style appended to connections

    @Test("addLinking appends plantuml style suffix to connection when style is configured")
    func addLinkingAppendsPlantumlStyleSuffix() {
        let style = RelationshipStyle()
        var config = Configuration.default
        config.relationships.inheritance = Relationship(label: "inherits", style: style)
        let ctx = DiagramContext(configuration: config)
        let child = SyntaxStructure(kind: .class, name: "Child")
        let parent = SyntaxStructure(kind: .class, name: "Parent")
        _ = ctx.uniqName(item: child, relationship: "inherits")
        ctx.addLinking(item: child, parent: parent)
        let conn = ctx.connections.first ?? ""
        #expect(conn.contains("#line:"))
    }

    @Test("uniqName appends plantuml style to extension connection when dependency style is configured")
    func uniqNameExtensionConnectionWithStyle() {
        let style = RelationshipStyle()
        let config = Configuration(
            relationships: RelationshipOptions(
                dependency: Relationship(label: "ext", style: style)
            )
        )
        let ctx = DiagramContext(configuration: config)
        let parent = SyntaxStructure(kind: .class, name: "Foo")
        let ext = SyntaxStructure(kind: .extension, name: "Foo")
        _ = ctx.uniqName(item: parent, relationship: "inherits")
        _ = ctx.uniqName(item: ext, relationship: "ext")
        #expect(ctx.extnConnections.first?.contains("#line:") == true)
    }
}
