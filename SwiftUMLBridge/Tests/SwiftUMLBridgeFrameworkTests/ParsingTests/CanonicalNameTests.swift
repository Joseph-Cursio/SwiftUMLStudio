import SwiftParser
import SwiftSyntax
import Testing
@testable import SwiftUMLBridgeFramework

/// `` `Plain` `` and `Plain` are one identifier, so the parsers read both as `Plain`. A name that
/// needs its backticks wherever it is written keeps them (#123).
@Suite("Canonical names")
struct CanonicalNameTests {

    /// The name token of `struct <spelling> {}`.
    private func structName(_ spelling: String) throws -> TokenSyntax {
        let file = Parser.parse(source: "struct \(spelling) {}")
        return try #require(file.statements.first?.item.as(StructDeclSyntax.self)).name
    }

    /// The type annotation of `var value: <spelling>`.
    private func annotation(_ spelling: String) throws -> TypeSyntax {
        let file = Parser.parse(source: "var value: \(spelling)")
        let variable = try #require(file.statements.first?.item.as(VariableDeclSyntax.self))
        return try #require(variable.bindings.first?.typeAnnotation?.type)
    }

    @Test("an escaped name that needs no escaping loses its backticks", arguments: [
        ("`Plain`", "Plain"), ("Plain", "Plain"), ("`type`", "type"), ("`Café`", "Café")
    ])
    func unneededBackticks(spelling: String, expected: String) throws {
        #expect(try structName(spelling).canonicalName == expected)
    }

    /// A type member named `Type` or `Protocol` must be escaped: after a `.`, the bare word is a metatype.
    @Test("a raw identifier, a keyword, Type and Protocol keep theirs", arguments: [
        "`Foo Bar`", "`default`", "`class`", "`self`", "`Type`", "`Protocol`"
    ])
    func neededBackticks(spelling: String) throws {
        #expect(try structName(spelling).canonicalName == spelling)
    }

    @Test("a type's description writes each name inside it canonically", arguments: [
        ("[`Pet`]", "[Pet]"),
        ("Dictionary<`Key`, [`Value`]>", "Dictionary<Key, [Value]>"),
        ("`Outer`.`Inner`?", "Outer.Inner?"),
        ("[`Foo Bar`]", "[`Foo Bar`]"),
        ("[String: Int]", "[String: Int]"),
        ("any `P` & /* both */ `Q`", "any P & /* both */ Q"),
        ("Outer.`Type`", "Outer.`Type`")
    ])
    func typeDescription(spelling: String, expected: String) throws {
        #expect(try annotation(spelling).canonicalDescription == expected)
    }

    /// A comment at either end of a node is trivia, not part of it (#128). One between its tokens
    /// stays, as the type witness above keeps `/* both */`.
    @Test("a node's description leaves out a comment beside it", arguments: [
        ("[`Pet`] // pets", "[Pet]"),
        ("[Pet] /* pets */", "[Pet]"),
        ("\n    // pets\n    [`Foo Bar`]", "[`Foo Bar`]")
    ])
    func commentBeside(spelling: String, expected: String) throws {
        #expect(try annotation(spelling).canonicalDescription == expected)
    }

    @Test("a typed-in dotted name reads each component as Swift does", arguments: [
        ("`Lamp`.`Light`", "Lamp.Light"), ("Outer.`Inner`", "Outer.Inner"), ("`Foo Bar`.Light", "`Foo Bar`.Light"),
        ("Lamp.Light", "Lamp.Light")
    ])
    func typedInDottedName(spelling: String, expected: String) {
        #expect(spelling.canonicalDottedName == expected)
    }

    @Test("a typed-in identifier reads as a parsed one does", arguments: [
        ("`Plain`", "Plain"), ("Plain", "Plain"), ("`Foo Bar`", "`Foo Bar`"), ("`default`", "`default`"),
        ("`Type`", "`Type`"), ("``", "``"), ("`", "`"), ("`a`b`", "`a`b`")
    ])
    func typedInIdentifier(spelling: String, expected: String) {
        #expect(spelling.canonicalIdentifier == expected)
    }
}
