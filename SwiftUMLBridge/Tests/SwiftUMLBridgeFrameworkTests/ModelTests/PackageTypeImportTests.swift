import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

/// `deps --types --package` tagged a supertype with the first target that declares its name,
/// whatever the writer's file imports, so where ModA and ModB each declare `open class Base` and
/// ModC's file imports only ModB, `final class C: Base {}` was drawn to `Base <<ModA>>` (#202).
/// The class diagram ends that edge on ModB's `Base`, as Swift does. Each end is now tagged with
/// the module of the declaration the class diagram ends it on. Every case builds with swiftc,
/// which resolves the member only the expected `Base` has.
@Suite("deps --types --package tags a supertype with the module the writer's file means")
struct PackageTypeImportTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let writer: String
        var reexporter = "public struct EThing {}"
        /// More of ModA's source, after its `Base` and `Proto`.
        var moreOfModA = ""
        /// More of ModB's source, after its `Base` and `Proto`.
        var moreOfModB = ""
        /// PlantUML lines that must appear: node declarations and edges.
        let lines: [String]
        /// A type whose node must carry no tag, so no `class` line names it.
        var untagged: String?
        /// Text that must not appear.
        var absent: [String] = []

        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(
            name: "the file imports only ModB", writer: "import ModB\n\nfinal class C: Base {}",
            lines: ["class \"Base\" as Base <<ModB>>"]
        ),
        Case(
            name: "the file imports only ModA", writer: "import ModA\n\nfinal class C: Base {}",
            lines: ["class \"Base\" as Base <<ModA>>"]
        ),
        Case(
            name: "the file imports both and qualifies the name with ModB",
            writer: "import ModA\nimport ModB\n\nfinal class C: ModB.Base {}",
            lines: ["class \"Base\" as Base <<ModB>>", "C --> Base : inherits"]
        ),
        Case(
            name: "the file reaches ModB's Base through its own typealias",
            writer: "import ModB\n\ntypealias Parent = Base\nfinal class C: Parent {}",
            lines: ["class \"Base\" as Base <<ModB>>"]
        ),
        Case(
            name: "the file extends Base, which is ModB's",
            writer: "import ModB\n\nprotocol Local {}\nextension Base: Local {}",
            lines: ["class \"Base\" as Base <<ModB>>"]
        ),
        Case(
            name: "a protocol both modules declare, conformed to where only ModB is imported",
            writer: "import ModB\n\nstruct S: Proto {}",
            lines: ["class \"Proto\" as Proto <<ModB>>"]
        ),
        Case(
            name: "the file imports ModE, which re-exports ModB",
            writer: "import ModE\n\nfinal class C: Base {}", reexporter: "@_exported import ModB",
            lines: ["class \"Base\" as Base <<ModB>>"]
        ),
        Case(
            name: "a declaration's own end: ModB's Thing, beside ModA's of that name",
            writer: "public struct CThing {}", moreOfModA: "public struct Thing {}",
            moreOfModB: "struct Thing: Proto {}", lines: ["class \"Thing\" as Thing <<ModB>>"]
        ),
        Case(
            name: "Swift's Identifiable, beside ModA's, which the file does not import",
            writer: "struct S: Identifiable {\n    let id: Int\n}",
            moreOfModA: "public protocol Identifiable {}", lines: [], untagged: "Identifiable"
        ),
        Case(
            name: "ModA's and ModB's Base, both edge ends, are two nodes spelled with their modules",
            writer: "import ModB\n\nfinal class C: Base {}",
            moreOfModA: "final class AA: Base {}", lines: [
                "class \"ModA.Base\" as ModA.Base <<ModA>>", "class \"ModB.Base\" as ModB.Base <<ModB>>",
                "AA --> ModA.Base : inherits", "C --> ModB.Base : inherits",
            ]
        ),
        Case(
            name: "a name written with its module meets that module's split node",
            writer: "import ModA\nimport ModB\n\nfinal class C: ModB.Base {}\nfinal class D: ModA.Base {}",
            moreOfModA: "final class AA: Base {}", moreOfModB: "final class BB: Base {}", lines: [
                "class \"ModA.Base\" as ModA.Base <<ModA>>", "class \"ModB.Base\" as ModB.Base <<ModB>>",
                "AA --> ModA.Base : inherits", "BB --> ModB.Base : inherits", "C --> ModB.Base : inherits",
                "D --> ModA.Base : inherits",
            ]
        ),
        Case(
            name: "ModA's own Identifiable, an edge end, splits from Swift's, which keeps its name",
            writer: "struct S: Identifiable {\n    let id: Int\n}",
            moreOfModA: "public protocol Identifiable: Proto {}", lines: [
                "class \"ModA.Identifiable\" as ModA.Identifiable <<ModA>>",
                "ModA.Identifiable --> Proto : conforms", "S --> Identifiable : conforms",
            ], untagged: "Identifiable"
        ),
        Case(
            name: "an extension written with its module meets that module's split node",
            writer: "import ModA\nimport ModB\n\nprotocol Local {}\nextension ModB.Base: Local {}",
            moreOfModA: "final class AA: Base {}",
            lines: ["AA --> ModA.Base : inherits", "ModB.Base --> Local : conforms"], absent: ["ModB.ModB.Base"]
        ),
        Case(
            name: "a type nested in ModA's enum ModA, written ModA.Base, stays apart from ModA's split Base",
            writer: "public struct CThing {}",
            moreOfModA: "final class AA: Base {}\n\n\(nestedModABase)",
            moreOfModB: "final class BB: Base {}", lines: [
                "AA --> ModA.Base : inherits", "BB --> ModB.Base : inherits", "T --> ModA.ModA.Base : conforms",
            ]
        ),
        Case(
            name: "a type nested in ModB's enum ModA, written ModA.Base, stays apart from ModA's split Base",
            writer: "public struct CThing {}", moreOfModA: "final class AA: Base {}",
            moreOfModB: "final class BB: Base {}\n\n\(nestedModABase)",
            lines: [
                "class \"ModA.Base\" as ModA.Base <<ModA>>", "class \"ModB.ModA.Base\" as ModB.ModA.Base <<ModB>>",
                "AA --> ModA.Base : inherits", "T --> ModB.ModA.Base : conforms",
            ]
        ),
        Case(
            name: "Swift's Identifiable, tagged by ModC's extension, keeps its name beside ModA's split one",
            writer: "struct S: Identifiable {\n    let id: Int\n}\n\nextension Identifiable {\n    func touch() {}\n}",
            moreOfModA: "public protocol Identifiable: Proto {}", lines: [
                "class \"ModA.Identifiable\" as ModA.Identifiable <<ModA>>",
                "class \"Identifiable\" as Identifiable <<ModC>>", "S --> Identifiable : conforms",
            ], absent: ["ModC.Identifiable"]
        ),
        Case(
            name: "ModA's extension of its own Identifiable does not tag Swift's, which ModC's S means",
            writer: "struct S: Identifiable {\n    let id: Int\n}",
            moreOfModA: "public protocol Identifiable {}\n\nextension Identifiable {\n    public func hello() {}\n}"
                + "\n\nstruct OwnId: Identifiable {}",
            lines: [
                "class \"ModA.Identifiable\" as ModA.Identifiable <<ModA>>", "OwnId --> ModA.Identifiable : conforms",
            ],
            untagged: "Identifiable"
        ),
        Case(
            name: "an extension of a typealias of ModB's Base ends on Base",
            writer: "import ModB\n\ntypealias BAlias = Base\nprotocol Local {}\nextension BAlias: Local {}",
            lines: ["class \"Base\" as Base <<ModB>>", "Base --> Local : conforms"], absent: ["BAlias"]
        ),
        Case(
            name: "a nested type whose module spelling is another's is spelled with its module again",
            writer: "public enum ModA {\n    open class Base {\n        public init() {}\n    }\n}\n\n"
                + "public enum ModC {\n    public enum ModA {\n        open class Base {\n"
                + "            public init() {}\n        }\n    }\n}\n\n"
                + "public final class X: ModA.Base {}\npublic final class Y: ModC.ModA.Base {}",
            moreOfModA: "final class AA: Base {}", moreOfModB: "final class BB: Base {}", lines: [
                "AA --> ModA.Base : inherits", "X --> ModC.ModA.Base : inherits",
                "Y --> ModC.ModC.ModA.Base : inherits",
            ]
        ),
    ]

    private static let nestedModABase = "public enum ModA {\n    public protocol Base {}\n}\n\nstruct T: ModA.Base {}"

    /// ModA's or ModB's source: its `Base` with a member only it has, its `Proto`, and `more`.
    static func declaring(_ member: String, then more: String) -> String {
        """
        open class Base {
            public init() {}
            public func \(member)() {}
        }

        public protocol Proto {}

        \(more)
        """
    }

    /// The layout graph that SVG and Studio's canvas draw has a node for each `Base`, in its own
    /// module's box, with its own edges.
    @Test("the layout graph draws ModA's and ModB's Base as two nodes in their modules' boxes")
    func layoutGraphSplitsSharedName() throws {
        let package = try TemporaryPackage([
            (name: "ModA", files: [
                (name: "A.swift", source: Self.declaring("aOnly", then: "final class AA: Base {}"))
            ]),
            (name: "ModB", files: [(name: "B.swift", source: Self.declaring("bOnly", then: ""))]),
            (name: "ModC", files: [(name: "C.swift", source: "import ModB\n\nfinal class C: Base {}")]),
        ])
        defer { package.remove() }
        let graph = try #require(DependencyGraphGenerator().generateScript(
            forPackage: package.description(), packageRoot: package.root, mode: .types,
            with: Configuration(format: .svg)
        ).layoutGraph)
        let modules = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0.module) })
        #expect(modules["ModA.Base"] == "ModA" && modules["ModB.Base"] == "ModB" && modules["Base"] == nil)
        let edges = Set(graph.edges.map { "\($0.sourceId) -> \($0.targetId)" })
        #expect(edges == ["AA -> ModA.Base", "C -> ModB.Base"])
    }

    /// A split name is spelled with its module's C99 name, as Swift code writes it, so a target
    /// named `changelog-authors` gives `changelog_authors.Author`, while its tag keeps the target's
    /// own name; a name only one module's type uses is left alone.
    @Test("a split name is spelled with the module's C99 name, and an unshared one is left alone")
    func splitNameSpelling() {
        let edges = PackageTypeEdge.drawn([
            PackageTypeEdge(
                edge: DependencyEdge(
                    from: "Author", toNode: "Codable", kind: .conforms, fromModule: "changelog-authors"
                ),
                fromDeclaring: "changelog-authors", toDeclaring: nil
            ),
            PackageTypeEdge(
                edge: DependencyEdge(
                    from: "Author", toNode: "MDocComponent", kind: .conforms,
                    fromModule: "generate-manual", toModule: "generate-manual"
                ),
                fromDeclaring: "generate-manual", toDeclaring: "generate-manual"
            ),
        ])
        #expect(edges.map(\.from) == ["changelog_authors.Author", "generate_manual.Author"])
        #expect(edges.map(\.toNode) == ["Codable", "MDocComponent"])
        #expect(edges.map(\.fromModule) == ["changelog-authors", "generate-manual"])
    }

    /// Each case is read with ModA's sources at `Sources/ModA`, read first, and at
    /// `Sources/ZModA`, read last, so no tag comes from which target is read first.
    @Test("a supertype is tagged with the module of the type the writer means", arguments: cases, [false, true])
    func tagsTheMeantModule(_ testCase: Case, modALast: Bool) throws {
        let package = try TemporaryPackage([
            (name: "ModA", files: [(name: "A.swift", source: Self.declaring("aOnly", then: testCase.moreOfModA))]),
            (name: "ModB", files: [(name: "B.swift", source: Self.declaring("bOnly", then: testCase.moreOfModB))]),
            (name: "ModC", files: [(name: "C.swift", source: testCase.writer)]),
            (name: "ModE", files: [(name: "E.swift", source: testCase.reexporter)]),
        ], paths: modALast ? ["ModA": "Sources/ZModA"] : [:])
        defer { package.remove() }
        let text = DependencyGraphGenerator().generateScript(
            forPackage: package.description(), packageRoot: package.root, mode: .types,
            with: Configuration(format: .plantuml)
        ).text
        for line in testCase.lines { #expect(text.contains(line), "\(text)") }
        for absent in testCase.absent { #expect(!text.contains(absent), "\(text)") }
        if let untagged = testCase.untagged {
            #expect(!text.contains("class \"\(untagged)\""), "\(text)")
            #expect(text.contains("--> \(untagged) :"), "\(text)")
        }
    }
}
