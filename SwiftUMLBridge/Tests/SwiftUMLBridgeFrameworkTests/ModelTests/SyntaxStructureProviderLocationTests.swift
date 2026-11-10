@testable import SwiftUMLBridgeFramework
import Testing

@Suite("SyntaxStructureProvider stamps sourceLocation from SwiftSyntax")
struct SyntaxStructureProviderLocationTests {

    @Test("create(from:) stamps line/column from the parsed source")
    func stampsLineAndColumn() throws {
        let source = """
        import Foundation

        class Foo {}

        struct Bar {}
        """
        let structure = try #require(SyntaxStructure.create(from: source))
        let items = try #require(structure.substructure)
        let foo = try #require(items.first { $0.name == "Foo" })
        let bar = try #require(items.first { $0.name == "Bar" })

        // `class Foo` is on line 3; `Foo` starts at column 7 (after `class `).
        let fooLocation = try #require(foo.sourceLocation)
        #expect(fooLocation.line == 3)
        #expect(fooLocation.column == 7)

        // `struct Bar` is on line 5; `Bar` starts at column 8 (after `struct `).
        let barLocation = try #require(bar.sourceLocation)
        #expect(barLocation.line == 5)
        #expect(barLocation.column == 8)
    }

    @Test("in-memory parsing leaves filePath empty")
    func filePathEmptyForInMemoryParse() throws {
        let structure = try #require(SyntaxStructure.create(from: "actor Worker {}"))
        let item = try #require(structure.substructure?.first)
        let location = try #require(item.sourceLocation)
        #expect(location.filePath.isEmpty)
    }
}
