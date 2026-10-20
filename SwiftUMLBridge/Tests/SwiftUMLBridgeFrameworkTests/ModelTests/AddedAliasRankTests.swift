import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// Where a typealias another module adds to a type ranks: ModB, which imports ModA, adds `X` to
/// ModA's `Foo` through a typealias or a module, and ModA's own `extension Foo` declares an `X`
/// of its own in another file. ModA cannot see ModB, so in ModA, `Foo.X` is ModA's `X`, also in
/// the file that declares `Foo`.
@Suite("A typealias another module adds to a type")
struct AddedAliasRankTests {

    private static let modA = """
        public struct Foo {
            public init() {}
        }

        open class Base {
            public init() {}
        }

        open class Other {
            public init() {}
        }

        final class UseA: Foo.X {}
        """

    private static let ownAlias = "extension Foo {\n    public typealias X = Base\n}\n"

    @Test("does not take over the type's own module's member in the type's file", arguments: [
        "import ModA\n\ntypealias FA = Foo\n\nextension FA {\n    public typealias X = Other\n}\n",
        "import ModA\n\ntypealias FA = ModA.Foo\n\nextension FA {\n    public typealias X = Other\n}\n",
        "import ModA\n\nextension ModA.Foo {\n    public typealias X = Other\n}\n"
    ], [ExtensionVisualization.all, .merged])
    func ownModuleMemberFirst(modB: String, mode: ExtensionVisualization) throws {
        for modBFirst in [false, true] {
            try expectOwnMember(modB: modB, mode: mode, modBFirst: modBFirst)
        }
    }

    private static let typesOnly = """
        public struct Foo {
            public init() {}
        }

        open class Base {
            public init() {}
        }

        open class Other {
            public init() {}
        }
        """

    /// ModB declares a `Foo` of its own with an `X`, and adds another `X` to ModA's `Foo`: in
    /// ModB, `Foo` is ModB's own, so `Foo.X` is ModB's `X`, whichever file comes first.
    @Test("does not take over the extension's own module's member there", arguments: [
        "import ModA\n\nstruct Foo {\n    typealias X = ModA.Base\n}\n",
        "import ModA\n\nstruct Foo {}\n\ntypealias MyFoo = Foo\n\nextension MyFoo {\n    typealias X = ModA.Base\n}\n"
    ], [
        "import ModA\n\nextension ModA.Foo {\n    public typealias X = ModA.Other\n}\n",
        "import ModA\n\ntypealias FA = ModA.Foo\n\nextension FA {\n    public typealias X = ModA.Other\n}\n"
    ])
    func extensionModuleMemberFirst(own: String, added: String) throws {
        let use = "import ModA\n\nfinal class UseB: Foo.X {}\n"
        for mode in [ExtensionVisualization.all, .merged] {
            for addedFirst in [false, true] {
                let modB = addedFirst ? [added, own, use] : [own, added, use]
                let files = [("ModA", Self.typesOnly)] + modB.map { ("ModB", $0) }
                let elements = ElementOptions(showExtensions: mode)
                let items = try moduleQualifiedItems(files)
                let svg = LayoutGraphBuilder.buildClassDiagram(
                    from: items, configuration: Configuration(elements: elements, format: .svg)
                )
                #expect(svg.edgeEnds.contains("UseB -> Base"), "\(mode), added first: \(addedFirst)")
                #expect(!svg.edgeEnds.contains("UseB -> Other"), "\(mode), added first: \(addedFirst)")
                let text = DiagramScript(
                    items: try moduleQualifiedItems(files), configuration: Configuration(elements: elements)
                ).text
                #expect(ClassDiagramIds.lines(of: text, containing: "UseB").filter { $0.contains("<|") }
                    == ["Base <|-- UseB : inherits"], "\(mode), added first: \(addedFirst)")
            }
        }
    }

    private func expectOwnMember(modB: String, mode: ExtensionVisualization, modBFirst: Bool) throws {
        let own: [(module: String?, source: String)] = [("ModA", Self.modA), ("ModA", Self.ownAlias)]
        let files = modBFirst ? [("ModB", modB)] + own : own + [("ModB", modB)]
        let items = try moduleQualifiedItems(files)
        let elements = ElementOptions(showExtensions: mode)
        let svg = LayoutGraphBuilder.buildClassDiagram(
            from: items, configuration: Configuration(elements: elements, format: .svg)
        )
        #expect(svg.edgeEnds.contains("UseA -> Base"), "ModB first: \(modBFirst)")
        #expect(!svg.edgeEnds.contains("UseA -> Other"), "ModB first: \(modBFirst)")
        let configuration = Configuration(elements: elements)
        let text = DiagramScript(items: try moduleQualifiedItems(files), configuration: configuration).text
        #expect(ClassDiagramIds.lines(of: text, containing: "UseA").filter { $0.contains("<|") }
            == ["Base <|-- UseA : inherits"], "ModB first: \(modBFirst)")
    }
}
