import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

// What a member an extension adds ranks by when no file has a module (#230): the extension's own
// file, not the extended type's. Ranked in the type's file, every such `Foo.X` was as near as any
// other to a writer elsewhere, so the first read won, in another target. Then ranked near the
// writer, it must not beat what the name means there: a member of the writer's own `Foo`, or what
// `Foo`'s body declares. Each fixture was checked as a package with `swift build`, with the
// `import` lines added that the fixtures leave out, and `--package` says the same as the expected
// ends, apart from the known wrong ones. Where the first read used to decide, the files are read in
// both orders.

private typealias Fixture = NearestDirectoryFixture

private func supertypeLines(in lines: [String]) -> Set<String> {
    Set(lines.filter { $0.contains("<|") })
}

@Suite("A member an extension adds ranks in the extension's file, without a module")
struct ExtensionMemberRankTests {

    private static let merged = ElementOptions(showExtensions: .merged)

    private static let outer: Fixture.File = (
        "/r/Sources/A/A.swift", "public struct Outer {}\npublic typealias Crate = Outer"
    )
    private static let extensionC: Fixture.File = (
        "/r/Sources/C/C.swift", "extension Crate { typealias Dee = RealC }\nclass RealC {}"
    )
    private static let extensionD: Fixture.File = (
        "/r/Sources/D/D.swift", "extension Crate { typealias Dee = RealD }\nclass RealD {}"
    )

    private func crate(_ writers: [Fixture.File] = [], reversed: Bool) -> [Fixture.File] {
        [Self.outer] + (reversed ? [Self.extensionD, Self.extensionC] : [Self.extensionC, Self.extensionD]) + writers
    }

    // MARK: Spelled through a typealias

    /// #230's `crate`, where `class ViaOuter` shares a file with one of the extensions.
    @Test("a writer takes the alias in its own file, in every format, however extensions are drawn",
          arguments: [ExtensionVisualization.all, .merged, .none], [false, true])
    func ownFile(mode: ExtensionVisualization, reversed: Bool) throws {
        let writer: Fixture.File = (
            "/r/Sources/D/D.swift",
            "extension Crate { typealias Dee = RealD }\nclass RealD {}\nclass ViaOuter: Outer.Dee {}"
        )
        let extensions = reversed ? [writer, Self.extensionC] : [Self.extensionC, writer]
        let files = [Self.outer] + extensions
        let elements = ElementOptions(showExtensions: mode)
        #expect(try Fixture.edges(files, elements).contains("ViaOuter -> RealD"))
        let plantuml = try Fixture.lines(files, .plantuml, elements)
        #expect(plantuml.contains("RealD <|-- ViaOuter : inherits"), "\(plantuml)")
        for format in [DiagramFormat.mermaid, .nomnoml] {
            let onWriter = try Fixture.lines(files, format, elements).filter { $0.contains("ViaOuter") }
            #expect(onWriter.contains { $0.contains("RealD") }, "\(format): \(onWriter)")
            #expect(!onWriter.contains { $0.contains("RealC") }, "\(format): \(onWriter)")
        }
    }

    /// No candidate is in either writer's own file, so it is the directory step that tells them
    /// apart. A dotted name with an extension's member among its candidates takes no shared answer.
    @Test("writers beside each extension take that extension's alias", arguments: [false, true])
    func sameDirectory(reversed: Bool) throws {
        let writers: [Fixture.File] = [
            ("/r/Sources/C/WC.swift", "class WC: Outer.Dee {}"),
            ("/r/Sources/D/WD.swift", "class WD: Outer.Dee {}")
        ]
        let files = crate(reversed ? writers.reversed() : writers, reversed: reversed)
        for elements in [ElementOptions(), Self.merged] {
            #expect(supertypeLines(in: try Fixture.lines(files, .plantuml, elements)) == [
                "RealC <|-- WC : inherits", "RealD <|-- WD : inherits"
            ])
            #expect(try Fixture.edges(files, elements).filter { $0.hasPrefix("W") }.sorted() == [
                "WC -> RealC", "WD -> RealD"
            ])
        }
    }

    /// Three writers inside `extension Outer` in each directory. A name built on the extension
    /// around them, with an extension's member among its candidates, is fitted by what the whole
    /// set holds, so it takes no answer the text formats keep for another writer (#252): no writer
    /// reads another directory's.
    @Test("writers inside an extension take their own directory's alias, not another's",
          arguments: [false, true])
    func sharedMemoKeepsDirectoriesApart(reversed: Bool) throws {
        func writers(_ directory: String) -> [Fixture.File] {
            (1...3).map { index in
                ("/r/Sources/\(directory)/W\(index).swift", "extension Outer { class W\(index)\(directory): Dee {} }")
            }
        }
        let every = writers("C") + writers("D")
        let files = crate(reversed ? every.reversed() : every, reversed: reversed)
        let expected = Set((1...3).flatMap { index in [
            "RealC <|-- Outer.W\(index)C : inherits", "RealD <|-- Outer.W\(index)D : inherits"
        ] })
        for elements in [ElementOptions(), Self.merged] {
            #expect(supertypeLines(in: try Fixture.lines(files, .plantuml, elements)) == expected)
        }
    }

    /// The path `deps --types`, sequence and activity follow typealiases along.
    @Test("the resolver the other diagrams follow goes by the writer's directory too", arguments: [false, true])
    func resolver(reversed: Bool) throws {
        let resolver = TypeAliasResolver(items: try Fixture.parsed(crate(reversed: reversed)))
        #expect(resolver.resolve("Outer.Dee", in: URL(fileURLWithPath: "/r/Sources/C/Use.swift")) == "RealC")
        #expect(resolver.resolve("Outer.Dee", in: URL(fileURLWithPath: "/r/Sources/D/Use.swift")) == "RealD")
    }

    // MARK: Merged, however it is spelled

    /// #230's `mixed`: `extension FA` was wrong with extensions drawn apart, and `extension Foo`,
    /// which spells the type directly, with them merged.
    @Test("merging ranks an alias as drawing it apart does, however the extension spells the type",
          arguments: [false, true], [false, true])
    func mergedSpellings(mergedExtensions: Bool, reversed: Bool) throws {
        let writers: [Fixture.File] = [
            ("/r/Sources/ModB/B.swift", "extension Foo { typealias X = RB }\nclass RB {}\nclass WB: Foo.X {}"),
            ("/r/Sources/ModC/C.swift", """
            typealias FA = Foo
            extension FA { typealias X = RC }
            class RC {}
            class WC: Foo.X {}
            """)
        ]
        let files: [Fixture.File] = [("/r/Sources/ModA/Foo.swift", "public struct Foo { public init() {} }")]
            + (reversed ? writers.reversed() : writers)
        let elements = mergedExtensions ? Self.merged : ElementOptions()
        #expect(supertypeLines(in: try Fixture.lines(files, .plantuml, elements)) == [
            "RB <|-- WB : inherits", "RC <|-- WC : inherits"
        ])
    }

    /// `extension Foo.X` merges by the lookup before merging, and the edge ends by the one after
    /// it. With `extension Outer` the alias ranked differently in each, so the members and the edge
    /// took different boxes; with `extension Crate` both took the first read, in another target.
    @Test("an extension of such an alias merges into the box an edge from its directory ends on",
          arguments: ["Crate", "Outer"], [false, true])
    func membersAndEdgeShareABox(spelling: String, reversed: Bool) throws {
        let extensions: [Fixture.File] = [
            ("/r/Sources/C/C.swift", "extension \(spelling) { typealias Dee = RealC }\nclass RealC {}"),
            ("/r/Sources/D/D.swift", "extension \(spelling) { typealias Dee = RealD }\nclass RealD {}")
        ]
        let files = [Self.outer] + (reversed ? extensions.reversed() : extensions) + [
            ("/r/Sources/D/Added.swift", "extension Outer.Dee { func added() {} }"),
            ("/r/Sources/D/W.swift", "class W: Outer.Dee {}")
        ]
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: try Fixture.parsed(files), configuration: Configuration(elements: Self.merged, format: .svg)
        )
        let box = try #require(graph.nodes.first { node in
            node.compartments.flatMap(\.items).contains { $0.contains("added") }
        })
        #expect(box.id == "RealD")
        #expect(graph.edges.map { "\($0.sourceId) -> \($0.targetId)" }.contains("W -> RealD"))
    }

    // MARK: What the name means to the writer

    /// `AF` is A's `Foo`, so the alias beside `W` is no member of `W`'s own `Foo`, B's. Ranked near
    /// the writer, it must not win for that.
    @Test("an alias added to another target's same-named type does not beat a member of the writer's own",
          arguments: [ExtensionVisualization.all, .merged, .none], [false, true])
    func writersOwnType(mode: ExtensionVisualization, reversed: Bool) throws {
        let targets: [Fixture.File] = [
            ("/r/Sources/A/Foo.swift", "public struct Foo { public init() {} }\npublic typealias AF = Foo"),
            ("/r/Sources/B/Foo.swift", "struct Foo { typealias X = RB }\nclass RB {}"),
            ("/r/Sources/B/E.swift", "extension AF { typealias X = RE }\nclass RE {}\nclass W: Foo.X {}")
        ]
        let files = reversed ? targets.reversed() : targets
        #expect(supertypeLines(in: try Fixture.lines(files, .plantuml, ElementOptions(showExtensions: mode))) == [
            "RB <|-- W : inherits"
        ])
    }

    /// `Login` is nearer `W` than `Core`, and `W` cannot see it. A file that saw both `X`s would not
    /// compile, and every file can see a `public` member, so one that compiles means the body's.
    @Test("an extension's alias in a sibling directory does not beat a public member of the type's body",
          arguments: ["Crate", "Foo"], [ExtensionVisualization.all, .merged, .none])
    func bodyBeforeExtension(spelling: String, mode: ExtensionVisualization) throws {
        let files: [Fixture.File] = [
            ("/r/Sources/Core/Foo.swift", """
            public struct Foo { public typealias X = RCore; public init() {} }
            public typealias Crate = Foo
            open class RCore { public init() {} }
            """),
            ("/r/Sources/Features/Login/E.swift", "extension \(spelling) { typealias X = RLogin }\nclass RLogin {}"),
            ("/r/Sources/Features/Profile/W.swift", "class W: Foo.X {}")
        ]
        #expect(supertypeLines(in: try Fixture.lines(files, .plantuml, ElementOptions(showExtensions: mode))) == [
            "RCore <|-- W : inherits"
        ])
    }

    /// An `internal` member of `Foo`'s body is out of sight in another target, so `W` compiles and
    /// means the extension's. Nothing but the extension's nearness tells them apart.
    @Test("an internal member of the type's body does not beat an extension beside the writer",
          arguments: [ExtensionVisualization.all, .merged, .none])
    func internalBodyMember(mode: ExtensionVisualization) throws {
        let files: [Fixture.File] = [
            ("/r/Sources/A/Foo.swift", "public struct Foo { typealias X = RA; public init() {} }\nclass RA {}"),
            ("/r/Sources/B/B.swift", "extension Foo { typealias X = RB }\nclass RB {}\nclass W: Foo.X {}")
        ]
        #expect(supertypeLines(in: try Fixture.lines(files, .plantuml, ElementOptions(showExtensions: mode))) == [
            "RB <|-- W : inherits"
        ])
    }

    /// `Zed` is first read among equally near `Foo`s, so `W` and the extension beside it both read
    /// `Foo` as `Zed`'s, where Swift reads `Lib`'s. So that a public member of `Zed`'s `Foo` looks
    /// like the body of the type `W` means, and only the extension's being beside `W` keeps it.
    @Test("a public member of an unrelated type read first does not beat an extension beside the writer",
          arguments: [ExtensionVisualization.all, .none], [false, true])
    func unrelatedTypeReadFirst(mode: ExtensionVisualization, reversed: Bool) throws {
        let targets: [Fixture.File] = [
            ("/r/Sources/Zed/Foo.swift", "public struct Foo { public typealias X = RZed }\npublic class RZed {}"),
            ("/r/Sources/Lib/Foo.swift", "public struct Foo { public init() {} }")
        ]
        let files = (reversed ? targets.reversed() : targets) + [
            ("/r/Sources/App/App.swift", "extension Foo { typealias X = RApp }\nclass RApp {}\nclass W: Foo.X {}")
        ]
        #expect(supertypeLines(in: try Fixture.lines(files, .plantuml, ElementOptions(showExtensions: mode))) == [
            "RApp <|-- W : inherits"
        ])
    }

    private static let nestedOwn: Fixture.File = ("/r/Sources/App/Core/Foo.swift", "struct Foo {}\nclass W: Foo.X {}")
    private static let nestedExtension: Fixture.File = (
        "/r/Sources/App/Ext/E.swift", "extension Foo { typealias X = RA }\nclass RA {}"
    )
    private static let nestedVendored: Fixture.File = (
        "/r/Sources/App/Core/Vendor/Foo.swift", "public struct Foo { public typealias X = RV }\npublic class RV {}"
    )

    /// `W`'s `Foo` is the one in its file, and the extension's too when that is read first: the
    /// vendored target's `Foo.X` then belongs to another, however near it is. #230's `nested`.
    @Test("a target nested beside the writer does not beat the writer's own type's extension",
          arguments: [ExtensionVisualization.all, .merged])
    func nestedTarget(mode: ExtensionVisualization) throws {
        let files = [Self.nestedOwn, Self.nestedExtension, Self.nestedVendored]
        #expect(supertypeLines(in: try Fixture.lines(files, .plantuml, ElementOptions(showExtensions: mode))) == [
            "RA <|-- W : inherits"
        ])
    }

    // MARK: A hidden nested type

    /// B's `V` ranked in `Foo`'s file, so in that file it shadowed `Foo`'s own alias, and `WA` lost
    /// its edge, though B depends on A and A cannot see `V`.
    @Test("a hidden nested type another directory's extension adds leaves the type's own alias to its file",
          arguments: [false, true])
    func hiddenNestedType(reversed: Bool) throws {
        let files: [Fixture.File] = [
            ("/r/Sources/A/Foo.swift", """
            public struct Foo { public typealias V = Base }
            open class Base { public init() {} }
            class WA: Foo.V {}
            """),
            ("/r/Sources/B/Ext.swift", "extension Foo { class V {} }")
        ]
        let elements = ElementOptions(showNestedTypes: false, showExtensions: .merged)
        let ordered = reversed ? files.reversed() : files
        #expect(supertypeLines(in: try Fixture.lines(ordered, .plantuml, elements)) == ["Base <|-- WA : inherits"])
        #expect(try Fixture.edges(ordered, elements) == ["WA -> Base"])
    }

    /// `V` in B's extension, merged into `Foo`, belongs to `Foo` though it ranks in B. Taken for
    /// another type's, it was no rival, and `W`'s edge moved to the alias in the other target.
    @Test("a hidden nested type merged from an extension still counts as a member of the extended type")
    func hiddenMergedMember() throws {
        let files: [Fixture.File] = [
            ("/r/Sources/A/Foo.swift", "public struct Foo { public init() {} }"),
            ("/r/Sources/B/B.swift", "extension Foo { class V {} }\nclass W: Foo.V {}"),
            ("/r/Sources/C/C.swift", "extension Foo { typealias V = RC }\nclass RC {}")
        ]
        let elements = ElementOptions(showNestedTypes: false, showExtensions: .merged)
        #expect(supertypeLines(in: try Fixture.lines(files, .plantuml, elements)) == ["Foo.V <|-- W : inherits"])
    }

    // MARK: Known wrong

    /// Known wrong, as on main: the extension is equally near both `Foo`s, so read first, the
    /// vendored one is the `Foo` it extends. No candidate then belongs to `W`'s `Foo`, and the
    /// nearest wins. Only a directory's name decides this order.
    @Test("known wrong: an extension equally near two same-named types extends the first read",
          arguments: [ExtensionVisualization.all, .merged])
    func nestedTargetReadFirst(mode: ExtensionVisualization) throws {
        let files = [Self.nestedVendored, Self.nestedOwn, Self.nestedExtension]
        #expect(supertypeLines(in: try Fixture.lines(files, .plantuml, ElementOptions(showExtensions: mode))) == [
            "RV <|-- W : inherits"
        ])
    }
}
