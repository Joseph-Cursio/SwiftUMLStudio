import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// Which of several same-named types of different modules a name means, as Swift reads it: a
/// bare name among the writer's own module and the modules its file imports, and a dotted name
/// as a member of the type its first component means there. Each case builds with swiftc, which
/// resolves the member only the expected supertype has, and the answer is the same whether
/// nested types are drawn or hidden.
@Suite("Same-named types of different modules, read through the file's imports")
struct ImportAwareRankTests {

    struct File: Sendable {
        let module: String
        let source: String
    }

    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let files: [File]
        /// A member only the box `C` inherits from lists, with nested types drawn; `nil` when
        /// that type is outside the diagram.
        let member: String?
        /// With nested types hidden, the name the text formats end `C`'s edge on when that type
        /// is a hidden nested one, which no box draws; `nil` when it is drawn either way.
        let hiddenLabel: String?

        var testDescription: String { name }
    }

    private static let fooWithClass = File(module: "ModA", source: """
        public struct Foo {
            public init() {}
            open class V {
                public init() {}
                public func vOnly() {}
            }
        }
        """)

    private static let fooWithAlias = File(module: "ModB", source: """
        open class Base {
            public init() {}
            public func baseOnly() {}
        }

        public struct Foo {
            public init() {}
            public typealias V = Base
        }
        """)

    private static let bareFoo = File(module: "ModA", source: "public struct Foo {\n    public init() {}\n}\n")

    private static let classAddedToFoo = File(module: "ModB", source: """
        import ModA

        extension ModA.Foo {
            open class V {
                public init() {}
                public func vOnly() {}
            }
        }

        public struct BThing {
            public init() {}
        }
        """)

    private static let aliasAddedToFoo = File(module: "ModD", source: """
        import ModA

        extension ModA.Foo {
            public typealias V = Other
        }

        open class Other {
            public init() {}
            public func otherOnly() {}
        }
        """)

    private static let projectArray = File(module: "ModA", source: """
        open class Base {
            public init() {}
            public func baseOnly() {}
        }

        public struct Array {
            public init() {}
            public typealias Box = Base
        }
        """)

    private static let boxInIntArray = File(module: "ModB", source: """
        extension [Int] {
            open class Box {
                public init() {}
                public func boxOnly() {}
            }
        }
        """)

    private static func writer(_ imports: String, _ supertype: String = "Foo.V") -> File {
        File(module: "ModC", source: imports + "\nfinal class C: \(supertype) {}\n")
    }

    static let cases: [Case] = [
        Case(name: "a bare name is the imported module's type", files: [
            File(module: "ModA", source: "open class Base {\n    public init() {}\n    public func aOnly() {}\n}\n"),
            File(module: "ModB", source: "open class Base {\n    public init() {}\n    public func bOnly() {}\n}\n"),
            writer("import ModB\n", "Base")
        ], member: "bOnly", hiddenLabel: nil),
        Case(name: "a bare name a module the file does not import declares is the outside type", files: [
            File(module: "ModA",
                 source: "open class NSObject {\n    public init() {}\n    public func projectOnly() {}\n}\n"),
            writer("import Foundation\n", "NSObject")
        ], member: nil, hiddenLabel: nil),
        Case(name: "the first component is the imported module's type", files: [
            fooWithClass, fooWithAlias, writer("import ModB\n")
        ], member: "baseOnly", hiddenLabel: nil),
        Case(name: "the first component is the other imported module's type", files: [
            fooWithClass, fooWithAlias, writer("import ModA\n")
        ], member: "vOnly", hiddenLabel: "Foo.V"),
        Case(name: "a scoped import shows the first component", files: [
            fooWithClass, fooWithAlias, writer("import struct ModA.Foo\n")
        ], member: "vOnly", hiddenLabel: "Foo.V"),
        Case(name: "a re-exported module shows the first component", files: [
            fooWithClass, fooWithAlias, File(module: "ModX", source: "@_exported import ModA\n"),
            writer("import ModX\n")
        ], member: "vOnly", hiddenLabel: "Foo.V"),
        Case(name: "the writer module's own typealias names another module's type", files: [
            fooWithClass, fooWithAlias, File(module: "ModC", source: "import ModA\n\ntypealias Foo = ModA.Foo\n"),
            writer("import ModB\n")
        ], member: "vOnly", hiddenLabel: "Foo.V"),
        Case(name: "a private typealias of another file names nothing", files: [
            fooWithClass, fooWithAlias,
            File(module: "ModC", source: "import ModA\n\nprivate typealias Foo = ModA.Foo\n"),
            writer("import ModB\n")
        ], member: "baseOnly", hiddenLabel: nil),
        Case(name: "a project type the file cannot see leaves the first component outside", files: [
            projectArray, boxInIntArray, writer("import ModB\n", "Array<Int>.Box")
        ], member: "boxOnly", hiddenLabel: "Array.Box"),
        Case(name: "a project type the file imports keeps the first component the project's", files: [
            projectArray, boxInIntArray, writer("import ModA\nimport ModB\n", "Array.Box")
        ], member: "baseOnly", hiddenLabel: nil),
        Case(name: "a member another file's import loads is the first component's", files: [
            bareFoo, classAddedToFoo, File(module: "ModE", source: """
                public struct Foo {
                    public init() {}
                    public typealias V = Other
                }

                open class Other {
                    public init() {}
                    public func otherOnly() {}
                }
                """),
            File(module: "ModC", source: "import ModB\n\nlet thing = BThing()\n"), writer("import ModA\n")
        ], member: "vOnly", hiddenLabel: "Foo.V"),
        Case(name: "a member of a module no file imports is not seen", files: [
            bareFoo, classAddedToFoo, aliasAddedToFoo, writer("import ModA\nimport ModD\n")
        ], member: "otherOnly", hiddenLabel: nil),
        Case(name: "a member of a module another file imports is seen", files: [
            bareFoo, classAddedToFoo, aliasAddedToFoo,
            File(module: "ModC", source: "import ModD\n\nstruct Holder {}\n"), writer("import ModA\n")
        ], member: "otherOnly", hiddenLabel: nil),
        Case(name: "of two members, the one another file's import loads is seen", files: [
            bareFoo, classAddedToFoo, aliasAddedToFoo,
            File(module: "ModC", source: "import ModB\n\nstruct Holder {}\n"), writer("import ModA\n")
        ], member: "vOnly", hiddenLabel: "Foo.V")
    ]

    /// Each case is read with its files in the order given and reversed, so no answer comes from
    /// which module's type is recorded first.
    @Test("a name means the type the file sees", arguments: cases, [false, true])
    func meansTheTypeTheFileSees(_ testCase: Case, reversed: Bool) throws {
        try Self.expectMeans(testCase, reversed: reversed)
    }

    /// Expects `C`'s edge to end where `testCase` says, in both extension modes, with nested
    /// types shown and hidden.
    static func expectMeans(_ testCase: Case, reversed: Bool) throws {
        let given = testCase.files.map { (module: Optional($0.module), source: $0.source) }
        let files = reversed ? given.reversed() : given
        let items = { try moduleQualifiedItems(files) }
        for mode in [ExtensionVisualization.all, .merged] {
            let shown = LayoutGraphBuilder.buildClassDiagram(
                from: try items(),
                configuration: Configuration(elements: ElementOptions(showExtensions: mode), format: .svg)
            )
            let expected = try testCase.member.map { ["C -> \(try #require(shown.owner(of: $0), "\(mode)"))"] } ?? []
            #expect(shown.edgeEnds.filter { $0.hasPrefix("C -> ") } == expected, "\(mode), nested types shown")

            let hidden = ElementOptions(showNestedTypes: false, showExtensions: mode)
            let hiddenGraph = LayoutGraphBuilder.buildClassDiagram(
                from: try items(), configuration: Configuration(elements: hidden, format: .svg)
            )
            let hiddenEnds = hiddenGraph.edgeEnds.filter { $0.hasPrefix("C -> ") }
            if let label = testCase.hiddenLabel {
                #expect(hiddenEnds.isEmpty, "\(mode), nested types hidden")
                let text = DiagramScript(items: try items(), configuration: Configuration(elements: hidden)).text
                #expect(ClassDiagramIds.lines(of: text, containing: "<|-- C ") == ["\(label) <|-- C : inherits"],
                        "\(mode), nested types hidden")
            } else {
                let expectedHidden = try testCase.member.map {
                    ["C -> \(try #require(hiddenGraph.owner(of: $0), "\(mode), hidden"))"]
                } ?? []
                #expect(hiddenEnds == expectedHidden, "\(mode), nested types hidden")
            }
        }
    }
}
