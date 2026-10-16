import Testing
@testable import SwiftUMLBridgeFramework

/// nomnoml names a node by its `id=`, or else by its title, while every Nomnoml edge names a node
/// by its alias. Declared under their titles alone, nested types, extensions and decorated headers
/// each got an empty stand-in box on their edges, and same-titled declarations merged (#69).
@Suite("Nomnoml class-diagram node ids")
struct NomnomlNodeIdTests {

    private func script(_ source: String) -> String {
        ClassDiagramGenerator().generateScript(for: source, with: Configuration(format: .nomnoml)).text
    }

    private func graph(_ source: String) throws -> NomnomlGraph {
        try NomnomlGraph(parsing: script(source))
    }

    /// Each node as `[id, type, title]`.
    private func nodes(_ graph: NomnomlGraph) -> [[String]] {
        graph.nodes.map { [$0.id, $0.type, $0.title] }
    }

    /// Each edge as `[start, arrow, end]`.
    private func edges(_ graph: NomnomlGraph) -> [[String]] {
        graph.edges.map { [$0.start, $0.type, $0.end] }
    }

    // MARK: - The issue's inputs

    @Test("each declaration is its own node, and every edge ends on one", arguments: [
        "struct Outer {\n    struct Inner {}\n}",
        "struct Foo {}\nextension Foo {}",
        "extension String {\n    func first() {}\n}\nextension String {\n    func second() {}\n}",
        "struct A { struct Inner { var fromA: Int } }\nstruct B { struct Inner { var fromB: Int } }",
        "struct Box<T> { struct Inner {} }",
        "@MainActor final class Model { enum State {} }",
        "struct Foo {}\nextension Foo { func bar() {} }\nextension Foo { struct Inner {} }"
    ])
    func everyEdgeEndsOnADeclaration(source: String) throws {
        let text = script(source)
        let graph = try NomnomlGraph(parsing: text)
        let declarations = text.split(separator: "\n").filter { $0.hasPrefix("[<") }
        #expect(graph.nodes.count == declarations.count, "\(text)")
        let ids = Set(graph.nodes.map(\.id))
        #expect(graph.edges.allSatisfy { ids.contains($0.start) && ids.contains($0.end) })
    }

    @Test("a nested type's edge reaches the box that declares it")
    func nestedType() throws {
        let graph = try graph("struct Outer {\n    struct Inner {}\n}")
        #expect(nodes(graph) == [["Outer", "struct", "Outer"], ["Outer.Inner", "struct", "Inner"]])
        #expect(edges(graph) == [["Outer", "+-", "Outer.Inner"]])
    }

    @Test("two extensions of one type keep their own members")
    func sameNamedExtensions() throws {
        let graph = try graph("extension String {\n    func first() {}\n}\nextension String {\n    func second() {}\n}")
        #expect(graph.nodes.map(\.compartments) == [[["String"], ["~first()"]], [["String"], ["~second()"]]])
    }

    @Test("same-named nested types in two types stay two boxes")
    func sameNamedNestedTypes() throws {
        let source = "struct A { struct Inner { var fromA: Int } }\nstruct B { struct Inner { var fromB: Int } }"
        let graph = try graph(source)
        #expect(graph.node("A.Inner")?.compartments == [["Inner"], ["~fromA: Int"]])
        #expect(graph.node("B.Inner")?.compartments == [["Inner"], ["~fromB: Int"]])
        #expect(edges(graph) == [["A", "+-", "A.Inner"], ["B", "+-", "B.Inner"]])
    }

    @Test("generics and attributes stay in the title, out of the id")
    func decoratedHeaders() throws {
        let box = try graph("struct Box<T> { struct Inner {} }")
        #expect(nodes(box) == [["Box", "struct", "Box <T>"], ["Box.Inner", "struct", "Inner"]])
        #expect(edges(box) == [["Box", "+-", "Box.Inner"]])
        let model = try graph("@MainActor final class Model { enum State {} }")
        #expect(nodes(model) == [["Model", "class", "Model <<MainActor>>"], ["Model.State", "enum", "State"]])
        #expect(edges(model) == [["Model", "+-", "Model.State"]])
    }

    @Test("an extension's edges start at the extension's own box")
    func extensionEdges() throws {
        let graph = try graph("struct Foo {}\nextension Foo { func bar() {} }\nextension Foo { struct Inner {} }")
        #expect(nodes(graph) == [
            ["Foo", "struct", "Foo"], ["Foo.Inner", "struct", "Inner"],
            ["Foo0", "extension", "Foo"], ["Foo1", "extension", "Foo"]
        ])
        #expect(graph.node("Foo")?.compartments == [["Foo"]])
        #expect(graph.node("Foo0")?.compartments == [["Foo"], ["~bar()"]])
        #expect(edges(graph) == [["Foo1", "+-", "Foo.Inner"], ["Foo0", "-->", "Foo"], ["Foo1", "-->", "Foo"]])
    }

    // MARK: - Names nomnoml can't take as written

    @Test("a raw identifier's space becomes a no-break space in its id, not in its title")
    func rawIdentifierWithSpace() throws {
        let graph = try graph("protocol P {}\nstruct `Foo Bar`: P {}\nextension `Foo Bar` {}")
        let id = "`Foo\u{00A0}Bar`"
        #expect(nodes(graph) == [
            ["P", "interface", "P"], [id, "struct", "`Foo Bar`"], [id + "0", "extension", "`Foo Bar`"]
        ])
        #expect(edges(graph) == [[id, "--:>", "P"], [id + "0", "-->", id]])
    }

    @Test("a raw identifier holding nomnoml's syntax is encoded in its id and escaped in its title")
    func rawIdentifierWithSyntax() throws {
        let graph = try graph("struct `a|b [c]` {}\nextension `a|b [c]` { struct Inner {} }")
        let id = "`a%7Cb\u{00A0}%5Bc%5D`"
        #expect(nodes(graph) == [
            [id, "struct", "`a/b (c)`"], [id + ".Inner", "struct", "Inner"], [id + "0", "extension", "`a/b (c)`"]
        ])
        #expect(edges(graph) == [[id + "0", "+-", id + ".Inner"], [id + "0", "-->", id]])
    }

    /// An undeclared supertype has no declaration, so nomnoml draws a box titled with its id. An
    /// attributed one, `@unchecked Sendable`, is named `Sendable` (#152), so a raw identifier holds
    /// the space.
    @Test("an undeclared supertype's box reads as written")
    func undeclaredSupertypeWithSpace() throws {
        let graph = try graph("final class Box: `Foo Bar` {}")
        let supertype = try #require(graph.node("`Foo\u{00A0}Bar`"))
        #expect(supertype.title == "`Foo\u{00A0}Bar`")
        #expect(edges(graph) == [["Box", "-:>", supertype.id]])
    }

    /// `Base <Int>` names the supertype `Base `; with the space kept, the edge end would be read as
    /// `Base` only because nomnoml trims it.
    @Test("a supertype written with a space before its arguments ends on the declared type")
    func supertypeWithSpacedArguments() throws {
        let text = script("class Base<T> {}\nclass D: Base <Int> {}")
        #expect(text.contains("[D] -:> inherits [Base]"), "\(text)")
        let graph = try NomnomlGraph(parsing: text)
        #expect(graph.nodes.map(\.id) == ["Base", "D"])
    }

    // MARK: - String.nomnomlIdentifier

    @Test("an ordinary Swift name is its own id", arguments: ["Foo", "Outer.Inner", "Foo0", "Café", "\"@MainActor\""])
    func ordinaryNames(name: String) {
        #expect(name.nomnomlIdentifier == name)
    }

    @Test("each character nomnoml reads as syntax is encoded", arguments: [
        (" ", "\u{00A0}"), ("<", "%3C"), (">", "%3E"), ("[", "%5B"), ("]", "%5D"), ("|", "%7C"),
        (";", "%3B"), ("\\", "%5C"), ("\n", "%0A"), ("\t", "%09"), ("%", "%25"), ("\u{00A0}", "%C2%A0")
    ])
    func reservedCharacters(character: String, encoded: String) {
        #expect("a\(character)b".nomnomlIdentifier == "a\(encoded)b")
    }

    @Test("whitespace around a name is dropped, as nomnoml drops it from an edge end")
    func surroundingWhitespace() {
        #expect(" a b\u{00A0}\t".nomnomlIdentifier == "a\u{00A0}b")
    }

    @Test("names that differ only in an encoded character keep different ids")
    func encodingIsInjective() {
        let names = ["a b", "a\u{00A0}b", "a%C2%A0b", "a%20b", "a%25b", "a%b"]
        #expect(Set(names.map(\.nomnomlIdentifier)).count == names.count)
    }
}
