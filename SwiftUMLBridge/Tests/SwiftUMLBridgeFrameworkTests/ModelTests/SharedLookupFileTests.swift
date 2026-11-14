import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

// What `TypeLookup.typeWithSureKind` keeps among writers (`LayoutGraphBuilder.SharedLookup`) must not
// carry one file's answer to a writer in another (#229). The memo's key holds no file, so each way a
// file is known to bear on a name has a test here, in both orders, since the first writer read sets
// the memo.

private func supertypeLines(in text: String) -> [String] {
    text.split(separator: "\n").map(String.init).filter { $0.contains("<|") }
}

/// Every inheritance clause among `items`, with the scope it is written in.
private func writers(in items: [SyntaxStructure]) -> [(written: String, scope: DeclarationScope)] {
    items.flatMap { item in
        (item.inheritedTypes ?? []).compactMap { inherited in
            inherited.name.map { ($0, DeclarationScope(of: item)) }
        } + writers(in: item.substructure ?? [])
    }
}

/// The answer each writer gets beside the others is the one it gets alone, whichever writer is
/// asked first: what the memo keeps changes how quick the lookup is, and never what it finds.
private func expectMemoChangesNoAnswer(_ items: [SyntaxStructure], _ elements: ElementOptions) {
    let prepared = items.preparedForClassDiagram(with: Configuration(elements: elements, format: .plantuml))
    let lookup = LayoutGraphBuilder.TypeLookup(of: prepared)
    let clauses = writers(in: prepared)
    #expect(!clauses.isEmpty, "no inheritance clause to check")
    func answer(
        _ clause: (written: String, scope: DeclarationScope), _ kinds: LayoutGraphBuilder.AliasKinds
    ) -> (ObjectIdentifier?, Bool) {
        let name = lookup.qualifiedName(ofWritten: clause.written, from: clause.scope)
        let found = lookup.typeWithSureKind(name, from: clause.scope, kinds: kinds)
        return (found.type?.declaration, found.kindIsSure)
    }
    for order in [clauses, clauses.reversed()] {
        let shared = LayoutGraphBuilder.AliasKinds()
        for clause in order {
            let beside = answer(clause, shared)
            let alone = answer(clause, LayoutGraphBuilder.AliasKinds())
            #expect(beside.0 == alone.0 && beside.1 == alone.1, "\(clause.written) in \(clause.scope.filePath ?? "?")")
        }
    }
}

@Suite("A writer takes no other file's answer from the shared memo")
struct SharedLookupFileTests {

    // MARK: Which candidates the writer can see

    /// A typealias only its file sees, which `mergeExtensions` ranks in `Foo`'s file: with a module,
    /// the first writer read kept a list of candidates holding its own alias alone.
    @Test("a writer sees its own file's merged typealias, however it is hidden from the rest",
          arguments: [
            ("extension Foo {\n    private typealias V = P1\n    struct W1: V {}\n}",
             "extension Foo {\n    private typealias V = P2\n    struct W2: V {}\n}"),
            ("extension Foo {\n    fileprivate typealias V = P1\n    struct W1: V {}\n}",
             "extension Foo {\n    fileprivate typealias V = P2\n    struct W2: V {}\n}"),
            ("private extension Foo { typealias V = P1 }\nextension Foo { struct W1: V {} }",
             "private extension Foo { typealias V = P2 }\nextension Foo { struct W2: V {} }"),
          ], [false, true])
    func mergedPrivateAlias(sources: (String, String), reversed: Bool) throws {
        let writerFiles = [sources.0, sources.1].map { (module: Optional("App"), source: $0) }
        let files = [(module: Optional("App"), source: "struct Foo {}\nprotocol P1 {}\nprotocol P2 {}")]
            + (reversed ? writerFiles.reversed() : writerFiles)
        let elements = ElementOptions(showExtensions: .merged)
        let text = DiagramScript(
            items: try moduleQualifiedItems(files), configuration: Configuration(elements: elements)
        ).text
        #expect(text.contains("P1 <|.. Foo.W1"), "\(text)")
        #expect(text.contains("P2 <|.. Foo.W2"), "\(text)")
        expectMemoChangesNoAnswer(try moduleQualifiedItems(files), elements)
    }

    // MARK: The fallback that reads a module qualifier

    /// Nothing is recorded under `ModA.Base`, so the candidates are empty and alike for both
    /// writers, and the answer comes from `Base`, the rest of the name, among what each can see.
    @Test("a name read through its module means what the writer's own file declares", arguments: [false, true])
    func moduleQualifiedPrivateType(reversed: Bool) throws {
        let writerFiles: [(module: String?, source: String)] = [
            ("ModA", "private class Base { func fromA() {} }\nprivate class W1: ModA.Base {}"),
            ("ModA", "private class Base { func fromC() {} }\nprivate class W3: ModA.Base {}"),
        ]
        let files = reversed ? writerFiles.reversed() : writerFiles
        let text = DiagramScript(items: try moduleQualifiedItems(files), configuration: Configuration()).text
        let expected = reversed ? ["Base <|-- W3 : inherits", "Base0 <|-- W1 : inherits"]
            : ["Base <|-- W1 : inherits", "Base0 <|-- W3 : inherits"]
        #expect(Set(supertypeLines(in: text)) == Set(expected), "\(text)")
        expectMemoChangesNoAnswer(try moduleQualifiedItems(files), ElementOptions())
    }

    @Test("so does one nested past the module", arguments: [false, true])
    func moduleQualifiedPrivateNestedType(reversed: Bool) throws {
        let writerFiles: [(module: String?, source: String)] = [
            ("ModA", "private enum Outer { class Base {} }\nprivate class W1: ModA.Outer.Base {}"),
            ("ModA", "private enum Outer { class Base {} }\nprivate class W3: ModA.Outer.Base {}"),
        ]
        let files = reversed ? writerFiles.reversed() : writerFiles
        let text = DiagramScript(items: try moduleQualifiedItems(files), configuration: Configuration()).text
        let expected = reversed ? ["Outer.Base <|-- W3 : inherits", "Outer.Base1 <|-- W1 : inherits"]
            : ["Outer.Base <|-- W1 : inherits", "Outer.Base1 <|-- W3 : inherits"]
        #expect(Set(supertypeLines(in: text)) == Set(expected), "\(text)")
        expectMemoChangesNoAnswer(try moduleQualifiedItems(files), ElementOptions())
    }

    /// `extension Crate` ranks its typealias in the file of the type `Crate` means, not its own, and
    /// `#if` lets two of one name stand. Read through the module, nothing is recorded under the name
    /// as written, so `localNearest` finds none, and that file alone ranks this one first.
    @Test("a name read through its module means what ranks in the writer's own file", arguments: [false, true])
    func moduleQualifiedRankedInWritersFile(reversed: Bool) throws {
        let writerFiles: [(module: String?, source: String)] = [
            ("ModA", """
            struct Foo {}
            typealias Crate = Foo
            #if !FLAG
            struct W1: ModA.Foo.V {}
            #endif
            """),
            ("ModA", "#if FLAG\nstruct W2: ModA.Foo.V {}\n#endif"),
        ]
        let files: [(module: String?, source: String)] = [
            ("ModA", "protocol P1 {}\nprotocol P2 {}"),
            ("ModA", "#if !FLAG\nextension Crate {\n    typealias V = P1\n}\n#endif"),
            ("ModA", "#if FLAG\nextension Foo {\n    typealias V = P2\n}\n#endif"),
        ] + (reversed ? writerFiles.reversed() : writerFiles)
        let text = DiagramScript(items: try moduleQualifiedItems(files), configuration: Configuration()).text
        #expect(
            Set(supertypeLines(in: text)) == ["P1 <|.. W1 : conforms to", "P2 <|.. W2 : conforms to"], "\(text)"
        )
        expectMemoChangesNoAnswer(try moduleQualifiedItems(files), ElementOptions())
    }

    /// `Mod.Inner.V`, built on `extension Mod.Inner`, gets no start, so the key does not tell a writer
    /// whose own `private enum Mod` keeps the module from being read (`shadows`) from one that reads
    /// it. Only `W2`'s edge is pinned: `W1`'s, an older gap, is not what Swift means either.
    @Test("a first component only the writer's file declares, in a name built on its extension",
          arguments: [false, true])
    func ownFirstComponentOfEnclosingExtension(reversed: Bool) throws {
        let writerFiles: [(module: String?, source: String)] = [
            ("App", """
            import Mod
            protocol V {}
            private enum Mod {
                enum Inner {}
            }
            extension Mod.Inner {
                struct W1: V {}
            }
            """),
            ("App", "import Mod\nextension Mod.Inner {\n    struct W2: V {}\n}"),
        ]
        let rivals: [(module: String?, source: String)] = [
            ("Mod", "public protocol PM {}\npublic struct Inner {\n    public typealias V = PM\n}"),
            ("X", """
            public protocol PX {}
            public enum Mod {
                public enum Inner {
                    public typealias V = PX
                }
            }
            """),
        ]
        let files = rivals + (reversed ? writerFiles.reversed() : writerFiles)
        let text = DiagramScript(items: try moduleQualifiedItems(files), configuration: Configuration()).text
        #expect(supertypeLines(in: text).contains("PM <|.. Mod.Inner.W2 : conforms to"), "\(text)")
        expectMemoChangesNoAnswer(try moduleQualifiedItems(files), ElementOptions())
    }

    // MARK: What the first component of a dotted name means

    private static let hiddenNestedTypes = ElementOptions(showNestedTypes: false)

    private static let firstComponentRivals: [NearestDirectoryFixture.File] = [
        ("sources/a.swift", "public struct Array {\n    public typealias V = Real2\n}"),
        ("sources/b.swift", "extension [Int] {\n    open class V {\n        public init() {}\n    }\n}"),
        ("sources/c.swift", "open class Real2 {\n    public init() {}\n}"),
    ]

    /// `Array` is the struct for `W1` and sugar for `W2`, read without a module, where no start
    /// tells them apart, and `V` is hidden, so what `W2` means shows only in `fitting`.
    @Test("a first component the writer's own file declares", arguments: [false, true])
    func ownFirstComponent(reversed: Bool) throws {
        let writerFiles: [NearestDirectoryFixture.File] = [
            ("sources/w1.swift", "open class W1: Array.V {}"),
            ("sources/w2.swift", "public typealias Array = [Int]\nopen class W2: Array.V {}"),
        ]
        let files = Self.firstComponentRivals + (reversed ? writerFiles.reversed() : writerFiles)
        let text = try NearestDirectoryFixture.lines(files, .plantuml, Self.hiddenNestedTypes).joined(separator: "\n")
        #expect(Set(supertypeLines(in: text)) == ["Real2 <|-- W1 : inherits", "Array.V <|-- W2 : inherits"], "\(text)")
        expectMemoChangesNoAnswer(try NearestDirectoryFixture.parsed(files), Self.hiddenNestedTypes)
    }

    /// The same, with the first component a member of a type around the alias that writes it,
    /// which no guard on the file's own top-level names sees, and no file in the memo's key
    /// would either: the two lookups are in one file. Both go through an alias so they ask at
    /// one depth, which the key holds.
    @Test("a first component only a type around the writer declares", arguments: [false, true])
    func enclosingFirstComponent(reversed: Bool) throws {
        let writerFiles = [
            "public typealias U = Array.V\nopen class W1: U {}",
            """
            public enum E {
                public typealias Array = [Int]
                public typealias T = Array.V
            }
            open class W2: E.T {}
            """,
        ]
        let source = (reversed ? writerFiles.reversed() : writerFiles).joined(separator: "\n")
        let files = Self.firstComponentRivals + [("sources/w.swift", source)]
        let text = try NearestDirectoryFixture.lines(files, .plantuml, Self.hiddenNestedTypes).joined(separator: "\n")
        #expect(Set(supertypeLines(in: text)) == ["Real2 <|-- W1 : inherits", "Array.V <|-- W2 : inherits"], "\(text)")
        expectMemoChangesNoAnswer(try NearestDirectoryFixture.parsed(files), Self.hiddenNestedTypes)
    }

    /// With nested types drawn, `[Int]`'s `V` is recorded under `Array.V` beside the struct's, so the
    /// candidates themselves are fitted by what `Array` means to the writer.
    @Test("a first component that decides among recorded candidates", arguments: [false, true])
    func ownFirstComponentAmongRecorded(reversed: Bool) throws {
        let writerFiles: [NearestDirectoryFixture.File] = [
            ("sources/w1.swift", "open class W1: Array.V {}"),
            ("sources/w2.swift", "public typealias Array = [Int]\nopen class W2: Array.V {}"),
        ]
        let files = Self.firstComponentRivals + (reversed ? writerFiles.reversed() : writerFiles)
        let text = try NearestDirectoryFixture.lines(files, .plantuml, ElementOptions()).joined(separator: "\n")
        #expect(Set(supertypeLines(in: text)) == ["Real2 <|-- W1 : inherits", "Array.V <|-- W2 : inherits"], "\(text)")
        expectMemoChangesNoAnswer(try NearestDirectoryFixture.parsed(files), ElementOptions())
    }

    // MARK: A hidden nested type

    /// `#if` lets two `Foo`s stand, one with a hidden `fileprivate` protocol `V`, the other a
    /// typealias. The protocol is no candidate, so its file holds nothing recorded under `Foo.V`, but
    /// it shadows the typealias there alone, and `W2`, which can't see it, must still reach the typealias.
    @Test("a hidden nested type only the writer's own file sees", arguments: [false, true])
    func ownHiddenNestedType(reversed: Bool) throws {
        let writerFiles: [(module: String?, source: String)] = [
            ("App", "#if !FLAG\nstruct Foo {\n    fileprivate protocol V {}\n}\nstruct W1: Foo.V {}\n#endif"),
            ("App", "#if FLAG\nstruct W2: Foo.V {}\n#endif"),
        ]
        let files: [(module: String?, source: String)] = [
            ("App", "protocol P {}\n#if FLAG\nstruct Foo {\n    typealias V = P\n}\n#endif")
        ] + (reversed ? writerFiles.reversed() : writerFiles)
        let elements = Self.hiddenNestedTypes
        let text = DiagramScript(
            items: try moduleQualifiedItems(files), configuration: Configuration(elements: elements)
        ).text
        #expect(Set(supertypeLines(in: text)) == ["Foo.V <|-- W1 : inherits", "P <|.. W2 : conforms to"], "\(text)")
        expectMemoChangesNoAnswer(try moduleQualifiedItems(files), elements)
    }

    // MARK: Writers the guard leaves sharing

    /// Only reading a first component as a module goes by the writer's file, so where no module has
    /// its name, a file that declares it shares, or each of its writers looks through every rival.
    /// `Parent` declares no `P`: one it did would be the member `Outer.P` means, which no rival's
    /// answer is (#250).
    @Test("writers in a file declaring a first component no module is named after still share")
    func ownFirstComponentNamingNoModuleShares() throws {
        let files: [(module: String?, source: String)] = [
            (nil, "public enum Outer {\n    public typealias P = Q\n}\npublic protocol Q {}"),
            (nil, """
            protocol R {}
            class Parent {}
            class Outer: Parent {}
            struct W1: Outer.P {}
            struct W2: Outer.P {}
            """),
        ]
        let items = try moduleQualifiedItems(files)
        let lookup = LayoutGraphBuilder.TypeLookup(of: items)
        let kinds = LayoutGraphBuilder.AliasKinds()
        for clause in writers(in: items) where clause.written == "Outer.P" {
            _ = lookup.typeWithSureKind(
                lookup.qualifiedName(ofWritten: clause.written, from: clause.scope), from: clause.scope, kinds: kinds
            )
        }
        #expect(kinds.shared.count == 1)
    }

    /// The guard goes by what a writer's own file holds, so writers whose files hold none of the
    /// name's types still share one lookup: without that, the memo saves nothing.
    @Test("writers whose files declare nothing of the name still share", arguments: [nil, "App"] as [String?])
    func othersStillShare(module: String?) throws {
        let files: [(module: String?, source: String)] = [
            (module, "class Base {}"),
            (module, "class W1: Base {}"),
            (module, "class W2: Base {}"),
            (module, "class W3: Base {}"),
        ]
        let items = try moduleQualifiedItems(files)
        let lookup = LayoutGraphBuilder.TypeLookup(of: items)
        let kinds = LayoutGraphBuilder.AliasKinds()
        func typeFound(by clause: (written: String, scope: DeclarationScope)) -> ObjectIdentifier? {
            lookup.typeWithSureKind(
                lookup.qualifiedName(ofWritten: clause.written, from: clause.scope), from: clause.scope, kinds: kinds
            ).type?.declaration
        }
        let clauses = writers(in: items)
        #expect(clauses.count == 3)
        #expect(typeFound(by: clauses[0]) != nil)
        #expect(kinds.shared.count == 1)
        // A wrong answer planted for each later writer shows it read what the first one kept:
        // the count alone stays 1 if the memo is never read, or only the first writer shares.
        let shared = try #require(kinds.shared.values.first)
        for clause in clauses.dropFirst() {
            shared.answerInDirectory[clause.scope.rankingDirectory] = (nil, true)
            #expect(typeFound(by: clause) == nil, "\(clause.scope.filePath ?? "?")")
        }
        #expect(kinds.shared.count == 1)
    }
}
