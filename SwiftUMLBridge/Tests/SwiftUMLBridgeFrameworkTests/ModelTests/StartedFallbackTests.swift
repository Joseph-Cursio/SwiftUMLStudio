import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// What a dotted name means when the type its first component means has none of the members
/// recorded under it: the fallback reads only the name as written, among types of modules the
/// file sees, and members of modules its module loads, so it never lands on a type the writer
/// cannot reach. Each case builds with swiftc, which resolves the member only the expected
/// supertype has (`ImportAwareRankTests`).
@Suite("A dotted name whose start has no member falls back to what the writer can reach")
struct StartedFallbackTests {
    typealias File = ImportAwareRankTests.File
    typealias Case = ImportAwareRankTests.Case

    /// A `Bar` of `module` with a nested `V` that lists `member`.
    static func barWithV(in module: String, member: String, access: String = "public ") -> File {
        File(module: module, source: """
            \(access)struct Bar {
                \(access)init() {}
                open class V {
                    \(access)init() {}
                    \(access)func \(member)() {}
                }
            }
            """)
    }

    static let aliasOfBar = File(module: "ModC", source: "import ModA\n\ntypealias Foo = ModA.Bar\n")

    static let cases: [Case] = [
        Case(name: "the writer file's own type named like an alias's target does not stand in for it", files: [
            barWithV(in: "ModA", member: "barOnly"),
            File(module: "ModC", source: """
                import ModA

                typealias Foo = ModA.Bar

                struct Bar {
                    class V {
                        func appOnly() {}
                    }
                }

                final class C: Foo.V {}
                """)
        ], member: "barOnly", hiddenLabel: "Bar.V"),
        Case(name: "a start misread by a re-export falls back past a member its module does not load", files: [
            File(module: "ModA", source: "public struct Foo {\n    public init() {}\n}\n"),
            File(module: "ModX", source: """
                @_exported import ModA

                public struct Foo {
                    public init() {}
                    open class V {
                        public init() {}
                        public func vOnly() {}
                    }
                }
                """),
            File(module: "ModB", source: """
                import ModA

                extension ModA.Foo {
                    open class V {
                        public init() {}
                        public func bOnly() {}
                    }
                }
                """),
            File(module: "ModC", source: "import ModX\n\nfinal class C: Foo.V {}\n")
        ], member: "vOnly", hiddenLabel: "Foo.V"),
        Case(name: "the fallback reads no type of a module the file does not import", files: [
            File(module: "Seen", source: """
                public struct Bar {}

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
            File(module: "Hidden", source: """
                public struct Foo {
                    public struct Inner {
                        open class W {
                            public init() {}
                            public func hOnly() {}
                        }
                    }
                }
                """),
            File(module: "App", source: "import Seen\n\nfinal class C: Foo.Inner.W {}\n")
        ], member: "wOnly", hiddenLabel: "Foo.Inner.W"),
        Case(name: "the fallback reads no member gathered under the start's own name", files: [
            File(module: "ModA", source: """
                public struct Bar {}

                public struct Foo {
                    public typealias Mid = Bar
                }

                open class AOther {
                    public init() {}
                    public func aOtherOnly() {}
                }

                extension Foo.Mid {
                    public typealias V = AOther
                }
                """),
            File(module: "ModB", source: """
                import ModA

                extension ModA.Foo.Mid {
                    open class V {
                        public init() {}
                        public func bOnly() {}
                    }
                }
                """),
            File(module: "ModC", source: "import ModA\n\nfinal class C: Foo.Mid.V {}\n")
        ], member: "aOtherOnly", hiddenLabel: nil)
    ]

    @Test("a name means the member Swift finds", arguments: cases, [false, true])
    func meansTheMemberSwiftFinds(_ testCase: Case, reversed: Bool) throws {
        try ImportAwareRankTests.expectMeans(testCase, reversed: reversed)
    }

    /// ModC's `typealias Foo = ModA.Outer.Bar` shadows ModA's own `Foo`, so `Foo.V` is
    /// `Outer.Bar.V` (swiftc: `barOnly` resolves, `fooOnly` does not). With nested types hidden,
    /// `Outer.Bar` is not looked up, so the alias leads nowhere; only drawn types are checked.
    @Test("a first component aliased to a nested type means that type's member", arguments: [false, true])
    func aliasOfNestedType(reversed: Bool) throws {
        let given: [(module: String?, source: String)] = [
            ("ModA", """
                public struct Foo {
                    public init() {}
                    open class V {
                        public init() {}
                        public func fooOnly() {}
                    }
                }

                public enum Outer {
                    public struct Bar {
                        public init() {}
                        open class V {
                            public init() {}
                            public func barOnly() {}
                        }
                    }
                }
                """),
            ("ModC", "import ModA\n\ntypealias Foo = ModA.Outer.Bar\n"),
            ("ModC", "import ModA\n\nfinal class C: Foo.V {}\n")
        ]
        let files = reversed ? given.reversed() : given
        for mode in [ExtensionVisualization.all, .merged] {
            let graph = LayoutGraphBuilder.buildClassDiagram(
                from: try moduleQualifiedItems(files),
                configuration: Configuration(elements: ElementOptions(showExtensions: mode), format: .svg)
            )
            let owner = try #require(graph.owner(of: "barOnly"), "\(mode)")
            #expect(graph.edgeEnds.filter { $0.hasPrefix("C -> ") } == ["C -> \(owner)"], "\(mode)")
        }
    }
}
