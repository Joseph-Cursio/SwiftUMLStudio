import Testing
@testable import SwiftUMLBridgeFramework
import SwiftParser
import SwiftSyntax

/// The extended type of the first extension in `extension <spelling> {}`.
private func extendedType(_ spelling: String) throws -> TypeSyntax {
    let file = Parser.parse(source: "extension \(spelling) {}")
    let decl = try #require(file.statements.first?.item.as(ExtensionDeclSyntax.self))
    return decl.extendedType
}

@Suite("TypeSyntax.extendedTypeName")
struct ExtendedTypeNameTests {

    @Test("a nominal keeps its name or dotted path, without generic arguments at any level", arguments: [
        ("Foo", "Foo"),
        ("Foo<Int>", "Foo"),
        ("Foo<Swift.Int>", "Foo"),
        ("Foo<[Int]>", "Foo"),
        ("Foo<Int,>", "Foo"),
        ("Swift.Array<Int>", "Swift.Array"),
        ("Swift.Result<Int, Error>", "Swift.Result"),
        ("Outer.Inner", "Outer.Inner"),
        ("Outer<Int>.Inner", "Outer.Inner"),
        ("Outer.Inner<Int>", "Outer.Inner"),
        ("Outer<Int>.Inner<String>", "Outer.Inner"),
        ("A.B.C", "A.B.C"),
        ("Outer . Inner", "Outer.Inner"),
        ("`Foo`", "`Foo`")
    ])
    func nominal(spelling: String, expected: String) throws {
        #expect(try extendedType(spelling).extendedTypeName == expected)
    }

    @Test("sugar names the standard library type it stands for", arguments: [
        ("[Int]", "Array"),
        ("[[Int]]", "Array"),
        ("[String: Int]", "Dictionary"),
        ("[3 of Int]", "InlineArray"),
        ("Int?", "Optional"),
        ("Int??", "Optional"),
        ("[Int]?", "Optional"),
        ("Foo<Int>?", "Optional"),
        ("Int!", "Optional"),
        ("(Int)", "Int"),
        ("((Foo<Int>))", "Foo"),
        ("[Int].Index", "Array.Index")
    ])
    func sugar(spelling: String, expected: String) throws {
        #expect(try extendedType(spelling).extendedTypeName == expected)
    }

    @Test("a type no extension can extend has no name", arguments: [
        "(Int, Int)", "()", "(x: Int)", "P & Q", "any P", "some P",
        "Foo.Type", "() -> Void", "~Copyable", "@Sendable Foo", "Foo."
    ])
    func nonNominal(spelling: String) throws {
        #expect(try extendedType(spelling).extendedTypeName == nil)
    }
}
