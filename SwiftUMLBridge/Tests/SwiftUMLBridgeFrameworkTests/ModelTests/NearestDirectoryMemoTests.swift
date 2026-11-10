import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

// What the text formats' lookup keeps among writers (`LayoutGraphBuilder.SharedLookup`) now that a
// name's answer goes by the writer's directory (#78), and what that costs.

private typealias Fixture = NearestDirectoryFixture

@Suite("The memo of a lookup that ranks by directory")
struct NearestDirectoryMemoTests {

    private static let candidates: [Fixture.File] = [
        ("PkgA/Sources/A/Base.swift", "class Base {}"),
        ("PkgB/Sources/B/Base.swift", "protocol Base {}")
    ]

    private func lookUpBase(
        from scope: DeclarationScope, in lookup: LayoutGraphBuilder.TypeLookup, kinds: LayoutGraphBuilder.AliasKinds
    ) -> (type: LayoutGraphBuilder.Declared?, kindIsSure: Bool) {
        lookup.typeWithSureKind(lookup.qualifiedName(ofWritten: "Base", from: scope), from: scope, kinds: kinds)
    }

    /// One lookup of a name's candidates serves writers in any number of directories, and each
    /// directory keeps its own answer. A key with the directory in it is correct too, but looks
    /// the candidates up again for each, which only a timing margin would catch.
    @Test("the shared memo keeps one set of candidates, and an answer per directory")
    func memoShape() throws {
        let lookup = LayoutGraphBuilder.TypeLookup(of: try Fixture.parsed(Self.candidates))
        let kinds = LayoutGraphBuilder.AliasKinds()
        for path in ["PkgA/Sources/A/SubA.swift", "PkgB/Sources/B/SubB.swift", "PkgB/Sources/B/SubC.swift"] {
            _ = lookUpBase(from: DeclarationScope(filePath: path, module: nil), in: lookup, kinds: kinds)
        }
        #expect(kinds.shared.count == 1)
        #expect(kinds.shared.values.first?.answerInDirectory.count == 2)
        #expect(kinds.shared.values.first?.everyComesToProtocol == false)
    }

    @Test("writers of one module share one answer, whatever their directories")
    func memoShapeWithModule() throws {
        let lookup = LayoutGraphBuilder.TypeLookup(of: try Fixture.parsed(Self.candidates))
        let kinds = LayoutGraphBuilder.AliasKinds()
        for path in ["PkgA/Sources/A/W.swift", "PkgB/Sources/B/W.swift"] {
            _ = lookUpBase(from: DeclarationScope(filePath: path, module: "App"), in: lookup, kinds: kinds)
        }
        #expect(kinds.shared.count == 1)
        let shared = try #require(kinds.shared.values.first)
        #expect(shared.answerInDirectory.count == 1)
        #expect(shared.answerInDirectory[nil] != nil)
    }

    // A wrong value planted in the memo shows it is read: losing either read changes no answer,
    // and neither shows in a timing bound.

    @Test("a directory's kept answer is the one a writer there gets")
    func answerIsRead() throws {
        let lookup = LayoutGraphBuilder.TypeLookup(of: try Fixture.parsed(Self.candidates))
        let kinds = LayoutGraphBuilder.AliasKinds()
        let scope = DeclarationScope(filePath: "PkgB/Sources/B/SubB.swift", module: nil)
        #expect(lookUpBase(from: scope, in: lookup, kinds: kinds).type != nil)
        let shared = try #require(kinds.shared.values.first)
        shared.answerInDirectory[scope.rankingDirectory] = (nil, true)
        #expect(lookUpBase(from: scope, in: lookup, kinds: kinds).type == nil)
    }

    @Test("whether every candidate comes to a protocol is worked out once")
    func everyIsRead() throws {
        let lookup = LayoutGraphBuilder.TypeLookup(of: try Fixture.parsed(Self.candidates))
        let kinds = LayoutGraphBuilder.AliasKinds()
        let scope = DeclarationScope(filePath: "PkgB/Sources/B/SubB.swift", module: nil)
        #expect(lookUpBase(from: scope, in: lookup, kinds: kinds).kindIsSure == false)
        let shared = try #require(kinds.shared.values.first)
        shared.everyComesToProtocol = true
        shared.answerInDirectory.removeAll()
        #expect(lookUpBase(from: scope, in: lookup, kinds: kinds).kindIsSure == true)
    }

    /// The ranking compares bytes, so the memo must too: as strings the two spellings of `café`
    /// are equal, and the second writer asked took the first's answer, in the text formats alone.
    @Test("composed and decomposed spellings of a directory keep answers of their own",
          arguments: [false, true])
    func directoryKeyIsItsBytes(reversedWriters: Bool) throws {
        let writers: [Fixture.File] = [
            ("caf\u{E9}/SubC.swift", "class SubC: Base {}"),
            ("cafe\u{301}/SubD.swift", "class SubD: Base {}")
        ]
        let files: [Fixture.File] = [
            ("caf\u{E9}/Base.swift", "class Base {}"),
            ("cafe\u{301}/Base.swift", "protocol Base {}")
        ] + (reversedWriters ? writers.reversed() : writers)
        let text = try Fixture.lines(files, .plantuml)
        #expect(text.contains("Base0 <|-- SubC : inherits"), "\(text)")
        #expect(text.contains("Base <|.. SubD : conforms to"), "\(text)")
    }

    /// A `private` alias in an extension is seen only in that file. Without a module it ranks
    /// there too (#230), so `W7` finds it before the memo, which this no longer exercises:
    /// `SharedLookupFileTests` does, with a module.
    /// `Foo.V` for `W0` is not what Swift means, `r/B/V.swift`'s `V`, an older gap: this pins only
    /// that `W0` never gets the alias, whichever is read first.
    @Test("a private alias a merged extension adds is not ranked for a writer that can't see it",
          arguments: [false, true])
    func privateAliasStaysItsOwnFiles(reversed: Bool) throws {
        let files: [Fixture.File] = [
            ("r/B/Ext/Ext.swift", "extension Foo { private typealias V = HelperP }\nextension Foo { struct W7: V {} }"),
            ("r/B/Foo.swift", "struct Foo {}\nextension Foo { struct W0: V {} }"),
            ("r/B/Helper.swift", "protocol HelperP {}"),
            ("r/B/V.swift", "protocol V {}"),
            ("r/A/Foo.swift", "struct Foo { protocol V {} }")
        ]
        let text = try Fixture.lines(
            reversed ? files.reversed() : files, .plantuml, ElementOptions(showExtensions: .merged)
        )
        #expect(text.contains("HelperP <|.. Foo.W7 : conforms to"), "\(text)")
        #expect(text.contains("Foo.V <|.. Foo.W0 : conforms to"), "\(text)")
    }

    /// The same when the other candidate is an alias too.
    @Test("nor when the other candidate is a typealias", arguments: [false, true])
    func privateAliasBesideAnotherAlias(reversed: Bool) throws {
        let files: [Fixture.File] = [
            ("r/B/Ext/Ext.swift", "extension Foo { private typealias V = HelperP }\nextension Foo { struct W7: V {} }"),
            ("r/B/Foo.swift", "struct Foo {}\nextension Foo { struct W0: V {} }"),
            ("r/B/Helper.swift", "protocol HelperP {}"),
            ("r/B/V.swift", "protocol V {}"),
            ("r/A/Foo.swift", "protocol Q {}\nstruct Foo { typealias V = Q }")
        ]
        let text = try Fixture.lines(
            reversed ? files.reversed() : files, .plantuml, ElementOptions(showExtensions: .merged)
        )
        #expect(text.contains("HelperP <|.. Foo.W7 : conforms to"), "\(text)")
        #expect(text.contains("Q <|.. Foo.W0 : conforms to"), "\(text)")
    }
}

@Suite("Ranking by directory stays quick")
struct NearestDirectoryCostTests {

    /// The bound is for a debug build, by this thread's CPU clock, so suites running beside this
    /// one do not count (8e939be). Each writer's scan is one comparison per candidate, not a
    /// split of each path, which took seconds; the memo shares the candidates among directories.
    private func cpuSeconds(_ work: () throws -> Void) rethrows -> Double {
        let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        try work()
        return Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start) / 1e9
    }

    @Test("many writers among many same-named types in many directories")
    func manyWritersAmongManyCandidates() throws {
        let root = "/Users/someone/Developer/a/rather/long/path/to/the/project/Sources"
        let files: [Fixture.File] = (0..<400).flatMap { index in
            [
                ("\(root)/Dir\(index)/Base.swift", "class Base {}"),
                ("\(root)/Dir\(index)/Sub.swift", "class Sub\(index): Base {}")
            ]
        }
        let items = try Fixture.parsed(files)
        var svg: [String] = []
        let svgTime = cpuSeconds {
            svg = LayoutGraphBuilder.buildClassDiagram(from: items, configuration: Configuration(format: .svg))
                .edges.map { "\($0.sourceId) -> \($0.targetId)" }
        }
        #expect(svgTime < 2, "\(svgTime)")
        #expect(svg.contains("Sub7 -> Base_7"))
        var text = ""
        let textTime = cpuSeconds {
            text = DiagramScript(items: items, configuration: Configuration(format: .plantuml)).text
        }
        #expect(textTime < 2, "\(textTime)")
        #expect(text.contains("Base6 <|-- Sub7 : inherits"))
    }

    /// 600 directories, each with a chain of typealiases through a type's members, every link in
    /// a sibling of the last's directory, so no two links of a chain share an answer.
    @Test("many alias chains across sibling directories")
    func manyChainsAcrossSiblingDirectories() throws {
        let members = (1..<8).map { "    typealias A\($0) = \($0 == 7 ? "Proto" : "NS.A\($0 + 1)")" }
            .joined(separator: "\n")
        let files: [Fixture.File] = (0..<600).flatMap { index in
            [
                ("/r/Dir\(index)/Alias/Alias.swift", "typealias A0 = NS.A1"),
                ("/r/Dir\(index)/NS/NS.swift", "struct NS {\n\(members)\n}"),
                ("/r/Dir\(index)/Proto/Proto.swift", "protocol Proto {}")
            ]
        } + [("/r/Dir0/Writer/Writer.swift", "struct Writer: A0 {}")]
        let items = try Fixture.parsed(files)
        var text = ""
        let elapsed = cpuSeconds {
            text = DiagramScript(items: items, configuration: Configuration(format: .plantuml)).text
        }
        #expect(elapsed < 2, "\(elapsed)")
        #expect(text.contains("<|.. Writer : conforms to"))
    }
}
