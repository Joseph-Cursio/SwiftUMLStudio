import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// Where reading a dotted name's first component through the file's imports needs more than the
/// imports: a tie Swift settles by shadowing, a typealias on the way, an extension the lookup cannot
/// follow, and the answers kept apart per file and per module name. Each case builds with swiftc,
/// which resolves the member only the expected supertype has (`ImportAwareRankTests`).
@Suite("A dotted name's start, where its first component's reading needs more than the imports")
struct NameStartFallbackTests {
    typealias File = ImportAwareRankTests.File
    typealias Case = ImportAwareRankTests.Case

    /// A `Foo` of `module` with a nested `V` that lists `member`.
    private static func fooWithV(in module: String, member: String = "vOnly", imports: String = "") -> File {
        File(module: module, source: imports + """
            public struct Foo {
                public init() {}
                open class V {
                    public init() {}
                    public func \(member)() {}
                }
            }
            """)
    }

    private static let plainFoo = File(module: "ModA", source: """
        public struct Foo {
            public init() {}
            public func aOnly() {}
        }
        """)

    static let cases: [Case] = [
        Case(name: "a first component a scoped import shadows keeps a member the whole import's lacks", files: [
            plainFoo, fooWithV(in: "ModB"),
            File(module: "ModC", source: "import ModA\nimport struct ModB.Foo\n\nfinal class C: Foo.V {}\n")
        ], member: "vOnly", hiddenLabel: "Foo.V"),
        Case(name: "a scoped import shadows a first component a whole import shows, both with the member", files: [
            fooWithV(in: "ModA", member: "aOnly"), fooWithV(in: "ModB"),
            File(module: "ModC", source: "import ModA\nimport struct ModB.Foo\n\nfinal class C: Foo.V {}\n")
        ], member: "vOnly", hiddenLabel: "Foo.V"),
        Case(name: "a module's own type shadows the one it re-exports, its member kept", files: [
            plainFoo, fooWithV(in: "ModX", imports: "@_exported import ModA\n\n"),
            File(module: "ModC", source: "import ModX\n\nfinal class C: Foo.V {}\n")
        ], member: "vOnly", hiddenLabel: "Foo.V"),
        Case(name: "an available type shadows an unavailable one, its member kept", files: [
            File(module: "ModA", source: "@available(*, unavailable, renamed: \"NewFoo\")\n" + plainFoo.source),
            fooWithV(in: "ModB"),
            File(module: "ModC", source: "import ModA\nimport ModB\n\nfinal class C: Foo.V {}\n")
        ], member: "vOnly", hiddenLabel: "Foo.V"),
        Case(name: "a scoped import shadows a bare name a whole import shows", files: [
            File(module: "ModA", source: "open class Base {\n    public init() {}\n    public func aOnly() {}\n}\n"),
            File(module: "ModB", source: "open class Base {\n    public init() {}\n    public func bOnly() {}\n}\n"),
            File(module: "ModC", source: "import ModA\nimport class ModB.Base\n\nfinal class C: Base {}\n")
        ], member: "bOnly", hiddenLabel: nil),
        Case(name: "a typealias declared in an extension of a nested type is a member of that type", files: [
            File(module: "ModA", source: """
                open class Base {
                    public init() {}
                    public func baseOnly() {}
                }

                public struct Foo {
                    public struct Inner {
                        public init() {}
                    }
                }

                extension Foo.Inner {
                    public typealias V = Base
                }
                """),
            File(module: "ModA", source: "final class C: Foo.Inner.V {}\n")
        ], member: "baseOnly", hiddenLabel: nil),
        Case(name: "a member typealias on the way leads to the type it aliases", files: [
            File(module: "ModA", source: """
                public struct Bar {
                    public init() {}
                }

                public struct Foo {
                    public typealias Inner = Bar
                }

                extension Foo.Inner {
                    open class W {
                        public init() {}
                        public func wOnly() {}
                    }
                }
                """),
            File(module: "ModA", source: "final class C: Foo.Inner.W {}\n")
        ], member: "wOnly", hiddenLabel: "Foo.Inner.W"),
        Case(name: "an extension spelled through another module's typealias keeps its member", files: [
            File(module: "ModA", source: """
                public struct Foo {
                    public struct V {}
                }

                public typealias Alias = Foo

                extension Alias.V {
                    open class Z {
                        public init() {}
                        public func zOnly() {}
                    }
                }
                """),
            File(module: "App", source: "import ModA\n\nfinal class C: Alias.V.Z {}\n")
        ], member: "zOnly", hiddenLabel: "Foo.V.Z"),
        Case(name: "a first component the writer module aliases to another type means that type's member", files: [
            File(module: "ModA", source: """
                public struct Foo {
                    public init() {}
                    open class V {
                        public init() {}
                        public func fooOnly() {}
                    }
                }

                public struct Bar {
                    public init() {}
                    open class V {
                        public init() {}
                        public func barOnly() {}
                    }
                }
                """),
            File(module: "ModC", source: "import ModA\n\ntypealias Foo = ModA.Bar\n"),
            File(module: "ModC", source: "import ModA\n\nfinal class C: Foo.V {}\n")
        ], member: "barOnly", hiddenLabel: "Bar.V")
    ]

    @Test("a name means the member Swift finds", arguments: cases, [false, true])
    func meansTheMemberSwiftFinds(_ testCase: Case, reversed: Bool) throws {
        try ImportAwareRankTests.expectMeans(testCase, reversed: reversed)
    }

    /// Each file of ModB nests its own `V` in `private extension ModA.Foo`, which only it sees, so
    /// each `Foo.V` is its own file's (swiftc: `CY` cannot call `onlyX`). The name is recorded as
    /// `ModA.Foo.V`, so an answer one file worked out must not be shared with the other.
    @Test("a member a file's private extension adds is that file's alone", arguments: [false, true])
    func privateMemberStaysInItsFile(reversed: Bool) throws {
        let given: [(module: String?, source: String)] = [
            ("ModA", "public struct Foo {\n    public init() {}\n}\n"),
            ("ModB", "import ModA\n\nprivate extension ModA.Foo {\n    class V {\n        func onlyX() {}\n    }\n}\n"
                + "\nprivate class CX: Foo.V {}\n"),
            ("ModB", "import ModA\n\nprivate extension ModA.Foo {\n    class V {\n        func onlyY() {}\n    }\n}\n"
                + "\nprivate class CY: Foo.V {}\n")
        ]
        let files = reversed ? [given[0], given[2], given[1]] : given
        for mode in [ExtensionVisualization.all, .merged] {
            let elements = ElementOptions(showExtensions: mode)
            let graph = LayoutGraphBuilder.buildClassDiagram(
                from: try moduleQualifiedItems(files), configuration: Configuration(elements: elements, format: .svg)
            )
            let text = DiagramScript(
                items: try moduleQualifiedItems(files), configuration: Configuration(elements: elements)
            ).text
            for (writer, member) in [("CX", "onlyX"), ("CY", "onlyY")] {
                let owner = try #require(graph.owner(of: member), "\(mode)")
                #expect(graph.edgeEnds.filter { $0.hasPrefix("\(writer) -> ") } == ["\(writer) -> \(owner)"], "\(mode)")
                let box = try #require(Self.plantUMLBox(listing: member, in: text), "\(mode)")
                #expect(ClassDiagramIds.lines(of: text, containing: "<|-- \(writer) ")
                    == ["\(box) <|-- \(writer) : inherits"], "\(mode)")
            }
        }
    }

    /// In ModC, which does not import the target Unicode, `Unicode` is Swift's, so the extension
    /// is one of Swift's `Unicode.Scalar` (swiftc: `value` resolves, the target's `projectOnly`
    /// does not), neither merged into nor linked to the target's `Unicode.Scalar`.
    @Test("a first component naming a target the file cannot write is a type outside the diagram")
    func firstComponentNamingAnUnwritableTarget() throws {
        let files: [(module: String?, source: String)] = [
            ("Unicode", """
                public enum Unicode {
                    public struct Scalar {
                        public init() {}
                        public func projectOnly() {}
                    }
                }
                """),
            ("ModC", "extension Unicode.Scalar {\n    func mine() -> Any { value }\n}\n")
        ]
        for mode in [ExtensionVisualization.all, .merged] {
            let graph = LayoutGraphBuilder.buildClassDiagram(
                from: try moduleQualifiedItems(files),
                configuration: Configuration(elements: ElementOptions(showExtensions: mode), format: .svg)
            )
            let scalar = try #require(graph.owner(of: "projectOnly"), "\(mode)")
            let ext = try #require(graph.owner(of: "mine"), "\(mode)")
            #expect(ext != scalar, "\(mode)")
            #expect(!graph.edgeEnds.contains { $0 == "\(ext) -> \(scalar)" || $0 == "\(scalar) -> \(ext)" }, "\(mode)")
        }
    }

    /// The id of the PlantUML box whose members include `member`.
    static func plantUMLBox(listing member: String, in text: String) -> String? {
        var box: String?
        for line in text.split(separator: "\n") {
            if line.hasPrefix("class "), let separator = line.range(of: " as ") {
                box = String(line[separator.upperBound...].prefix { $0 != " " })
            } else if line.contains(member) {
                return box
            }
        }
        return nil
    }
}
