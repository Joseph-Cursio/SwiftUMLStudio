import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// Which of several same-named members a dotted name means: one of the type its first component
/// means, from a module that the writer's module loads through any of its files' imports, a file
/// that declares nothing included, and theirs in turn. Each case builds with swiftc, which
/// resolves the member only the expected supertype has (`ImportAwareRankTests`).
@Suite("Members of the type a name starts at, read through the modules a module loads")
struct LoadedModuleMemberTests {
    typealias File = ImportAwareRankTests.File
    typealias Case = ImportAwareRankTests.Case

    private static let bareFoo = File(module: "ModA", source: "public struct Foo {\n    public init() {}\n}\n")

    /// An `open class V` with `member`, added to ModA's `Foo` in `module`.
    private static func classAddedToFoo(in module: String, member: String, spelled: String = "ModA.Foo") -> File {
        File(module: module, source: """
            import ModA

            extension \(spelled) {
                open class V {
                    public init() {}
                    public func \(member)() {}
                }
            }
            """)
    }

    /// ModC's own `Foo`, with a nested `V` that lists `cOnly`.
    private static let fooOfModC = File(module: "ModC", source: """
        public struct Foo {
            public init() {}
            open class V {
                public init() {}
                public func cOnly() {}
            }
        }
        """)

    static let cases: [Case] = [
        // ModD's class would come first, a type before a typealias, were ModB's not seen.
        Case(name: "a module that declares nothing loads the module it imports", files: [
            bareFoo, classAddedToFoo(in: "ModD", member: "dOnly"), File(module: "ModB", source: """
                import ModA

                extension ModA.Foo {
                    public typealias V = Other
                }

                open class Other {
                    public init() {}
                    public func otherOnly() {}
                }
                """),
            File(module: "ModX", source: "import ModB\n"),
            File(module: "ModC", source: "import ModA\nimport ModX\n\nfinal class C: Foo.V {}\n")
        ], member: "otherOnly", hiddenLabel: nil),
        Case(name: "a file that declares nothing loads the module it imports", files: [
            classAddedToFoo(in: "AClass", member: "aOnly"), bareFoo, classAddedToFoo(in: "ZClass", member: "vOnly"),
            File(module: "ModC", source: "import ZClass\n\nfunc load() {}\n"),
            File(module: "ModC", source: "import ModA\n\nfinal class C: Foo.V {}\n")
        ], member: "vOnly", hiddenLabel: "Foo.V"),
        Case(name: "the writer module's own member of a type the file does not import is not seen", files: [
            bareFoo, classAddedToFoo(in: "ModB", member: "extOnly"), fooOfModC,
            File(module: "ModB", source: "import ModC\n\nfinal class C: Foo.V {}\n")
        ], member: "cOnly", hiddenLabel: "Foo.V"),
        Case(name: "the writer module's own member, spelled bare, of a type the file does not import", files: [
            bareFoo, classAddedToFoo(in: "ModB", member: "extOnly", spelled: "Foo"), fooOfModC,
            File(module: "ModB", source: "import ModC\n\nfinal class C: Foo.V {}\n")
        ], member: "cOnly", hiddenLabel: "Foo.V"),
        Case(name: "a type declared under each of two `#if`s is one type", files: [
            File(module: "ModA", source: "#if os(Linux)\npublic struct Foo {\n    public init() {}\n}\n#endif\n"),
            File(module: "ModA", source: """
                #if !os(Linux)
                public struct Foo {
                    public init() {}
                }

                extension Foo {
                    open class V {
                        public init() {}
                        public func vOnly() {}
                    }
                }
                #endif
                """),
            File(module: "ModC", source: "import ModA\n\nfinal class C: Foo.V {}\n")
        ], member: "vOnly", hiddenLabel: "Foo.V"),
        Case(name: "a bare name never means a type nested in a module's namesake enum", files: [
            File(module: "Other",
                 source: "open class Base {\n    public init() {}\n    public func otherOnly() {}\n}\n"),
            File(module: "App", source: "enum App {\n    class Base {\n        func appOnly() {}\n    }\n}\n"),
            File(module: "App", source: "import Other\n\nfinal class C: Base {}\n")
        ], member: "otherOnly", hiddenLabel: nil)
    ]

    @Test("a name means the member the writer's module loads", arguments: cases, [false, true])
    func meansTheLoadedMember(_ testCase: Case, reversed: Bool) throws {
        try ImportAwareRankTests.expectMeans(testCase, reversed: reversed)
    }

    /// Read without their package, the files have no modules, so imports cannot tell the two
    /// `Base`s apart: the name means the first recorded, as before imports were read.
    @Test("without modules, a name means the first of its candidates, as before", arguments: [false, true])
    func directoryModeKeepsTheFirst(reversed: Bool) throws {
        let given: [(module: String?, source: String)] = [
            (nil, "class Base {\n    func aOnly() {}\n}\n"),
            (nil, "class Base {\n    func bOnly() {}\n}\n"),
            (nil, "import ModB\n\nfinal class C: Base {}\n")
        ]
        let files = reversed ? [given[1], given[0], given[2]] : given
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: try moduleQualifiedItems(files), configuration: Configuration(format: .svg)
        )
        let first = try #require(graph.owner(of: reversed ? "bOnly" : "aOnly"))
        #expect(graph.edgeEnds.filter { $0.hasPrefix("C -> ") } == ["C -> \(first)"])
    }
}
