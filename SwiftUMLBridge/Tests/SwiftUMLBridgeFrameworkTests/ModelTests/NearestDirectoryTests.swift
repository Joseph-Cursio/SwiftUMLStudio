import Testing
@testable import SwiftUMLBridgeFramework

/// Read without their package, files have no module, so of same-named types in other files a name
/// means the one whose file shares the most leading directories with the writer's, the first of
/// those on a tie, and the first of all when none shares any (#78). Each pick is read in both file
/// orders, since "first" is all the rule falls back on.
@Suite("Without modules, a name means the same-named type nearest by directory")
struct NearestDirectoryTests {

    private func declared(
        _ kind: ElementKind, _ name: String, in file: String?, module: String? = nil,
        inheriting inheritedTypes: [String] = []
    ) -> SyntaxStructure {
        let item = SyntaxStructure(
            inheritedTypes: inheritedTypes.isEmpty ? nil : inheritedTypes.map { SyntaxStructure(name: $0) },
            kind: kind, name: name
        )
        item.sourceLocation = file.map { SourceLocation(filePath: $0, line: 1, column: 1) }
        item.module = module
        return item
    }

    private func edges(_ items: [SyntaxStructure]) -> [String] {
        LayoutGraphBuilder.buildClassDiagram(from: items, configuration: Configuration(format: .svg))
            .edges.map { "\($0.sourceId) -> \($0.targetId)" }
    }

    /// `Sub`'s edge, with a `class Base` in each of `candidates`, in order, and `Sub` in `writer`.
    private func subEdge(_ writer: String?, among candidates: [String?]) -> [String] {
        edges(candidates.map { declared(.class, "Base", in: $0) }
              + [declared(.class, "Sub", in: writer, inheriting: ["Base"])])
    }

    /// The edge to the `Base` in the candidate at `index`, as the node ids are issued in order.
    private func end(at index: Int) -> String {
        index == 0 ? "Sub -> Base" : "Sub -> Base_\(index)"
    }

    struct Pick: CustomTestStringConvertible, Sendable {
        let label: String
        let writer: String
        let candidates: [String]
        /// The candidate meant in either order; `nil` for whichever is read first.
        let meant: String?
        var testDescription: String { label }
    }

    static let picks: [Pick] = [
        Pick(label: "the issue's case: the writer's own package", writer: "PkgB/Sources/B/Sub.swift",
             candidates: ["PkgA/Sources/A/Base.swift", "PkgB/Sources/B/Base.swift"],
             meant: "PkgB/Sources/B/Base.swift"),
        Pick(label: "absolute paths", writer: "/r/PkgB/Sources/B/Sub.swift",
             candidates: ["/r/PkgA/Sources/A/Base.swift", "/r/PkgB/Sources/B/Base.swift"],
             meant: "/r/PkgB/Sources/B/Base.swift"),
        Pick(label: "a writer deeper than the candidate", writer: "m/PkgB/Sources/B/Deep/Er/Sub.swift",
             candidates: ["m/PkgA/Sources/A/Base.swift", "m/PkgB/Sources/B/Base.swift"],
             meant: "m/PkgB/Sources/B/Base.swift"),
        Pick(label: "a sibling target of the writer's package", writer: "m/PkgB/Sources/B2/Sub.swift",
             candidates: ["m/PkgA/Sources/A/Base.swift", "m/PkgB/Sources/B1/Base.swift"],
             meant: "m/PkgB/Sources/B1/Base.swift"),
        Pick(label: "a test target's own double", writer: "Tests/FooTests/SubTests.swift",
             candidates: ["Sources/Foo/Base.swift", "Tests/FooTests/Mocks/Base.swift"],
             meant: "Tests/FooTests/Mocks/Base.swift"),
        Pick(label: "a production writer passes a test target over", writer: "Sources/Foo/Sub.swift",
             candidates: ["Tests/FooTests/Base.swift", "Sources/Bar/Base.swift"], meant: "Sources/Bar/Base.swift"),
        Pick(label: "the deepest shared directory wins", writer: "a/b/c/Sub.swift",
             candidates: ["a/Base.swift", "a/b/Base.swift"], meant: "a/b/Base.swift"),
        Pick(label: "below the writer's directory counts in full", writer: "a/b/Sub.swift",
             candidates: ["a/Base.swift", "a/b/c/d/Base.swift"], meant: "a/b/c/d/Base.swift"),
        Pick(label: "Xcode groups", writer: "MyApp/Views/V.swift",
             candidates: ["MyAppWidget/Base.swift", "MyApp/Models/Base.swift"], meant: "MyApp/Models/Base.swift"),
        Pick(label: "a directory shared beats the root alone", writer: "/c/e/Sub.swift",
             candidates: ["/x/a/Base.swift", "/c/d/Base.swift"], meant: "/c/d/Base.swift"),

        // Nothing tells them apart, so the rule falls to the first.
        Pick(label: "below the writer's directory is as near as beside it", writer: "r/a/Sub.swift",
             candidates: ["r/a/x/y/Base.swift", "r/a/Base.swift"], meant: nil),
        Pick(label: "equally near siblings", writer: "Sources/App/V.swift",
             candidates: ["Sources/Zed/Base.swift", "Sources/Core/Base.swift"], meant: nil),
        Pick(label: "the scan's root alone", writer: "/repo/C/Sub.swift",
             candidates: ["/repo/A/Base.swift", "/repo/B/Base.swift"], meant: nil),
        Pick(label: "the file system's root alone", writer: "/home/C/Sub.swift",
             candidates: ["/opt/A/Base.swift", "/usr/B/Base.swift"], meant: nil),
        Pick(label: "a directory whose name starts with another's", writer: "Sources/FooBar/Sub.swift",
             candidates: ["Sources/Zed/Base.swift", "Sources/Foo/Base.swift"], meant: nil),
        Pick(label: "a file named as the writer's directory", writer: "Pkg/Foo/Sub.swift",
             candidates: ["Pkg/Zed/Base.swift", "Pkg/Foo"], meant: nil),
        Pick(label: "an absolute writer and relative candidates", writer: "/PkgB/Sub.swift",
             candidates: ["Other/Base.swift", "PkgB/Base.swift"], meant: nil),
        Pick(label: "a relative writer and absolute candidates", writer: "PkgB/Sub.swift",
             candidates: ["/Other/Base.swift", "/PkgB/Base.swift"], meant: nil),
        Pick(label: "only the root shared with one candidate", writer: "/c/Sub.swift",
             candidates: ["a/Base.swift", "/b/Base.swift"], meant: nil),
        Pick(label: "bare file names", writer: "C.swift", candidates: ["A.swift", "B.swift"], meant: nil),
        Pick(label: "a writer in no directory", writer: "Sub.swift",
             candidates: ["A/Base.swift", "B/Base.swift"], meant: nil),
        Pick(label: "a writer directly under the root", writer: "/Sub.swift",
             candidates: ["/A/Base.swift", "/B/Base.swift"], meant: nil),
        Pick(label: "a writer parsed from a string", writer: "",
             candidates: ["A/Base.swift", "B/Base.swift"], meant: nil),
        Pick(label: "the root spelled with two slashes", writer: "//a/W.swift",
             candidates: ["/c/Base.swift", "//b/Base.swift"], meant: nil),
        Pick(label: "a writer directly under a root spelled with two slashes", writer: "//W.swift",
             candidates: ["/c/Base.swift", "//b/Base.swift"], meant: nil),

        // Known limit: paths are compared as spelled. Each writer is in the second candidate's
        // directory, but its path does not say so, so the first is taken, wrongly when it is the other.
        Pick(label: "two spellings of a symlink", writer: "/tmp/proj/PkgB/Sub.swift",
             candidates: ["/private/tmp/proj/PkgA/Base.swift", "/private/tmp/proj/PkgB/Base.swift"], meant: nil),
        Pick(label: "a path spelled with a dot", writer: "/d/./Sub/W.swift",
             candidates: ["/d/Other/Base.swift", "/d/Sub/Base.swift"], meant: nil),

        // Known wrong: a directory is not a module. Swift means the first candidate, one the
        // writer's file imports or one in the writer's own target, but a moduleless file's imports
        // and target are not read, so the nearer directory wins.
        Pick(label: "known wrong: another test target beats the code under test",
             writer: "Tests/FooTests/SubTests.swift",
             candidates: ["Sources/Foo/Base.swift", "Tests/BarTests/Base.swift"], meant: "Tests/BarTests/Base.swift"),
        Pick(label: "known wrong: a sibling target beats a dependency elsewhere", writer: "Sources/App/V.swift",
             candidates: ["Packages/Core/Sources/Core/Base.swift", "Sources/AppMocks/Base.swift"],
             meant: "Sources/AppMocks/Base.swift"),
        Pick(label: "known wrong: an example's sibling beats the library",
             writer: "Examples/Demo/Sources/Demo2/V.swift",
             candidates: ["Sources/Lib/Base.swift", "Examples/Demo/Sources/Demo1/Base.swift"],
             meant: "Examples/Demo/Sources/Demo1/Base.swift"),
        Pick(label: "known wrong: a folder no target compiles beats the writer's target",
             writer: "Sources/App/Features/Login/V.swift",
             candidates: ["Sources/App/Base.swift", "Sources/App/Features/Login/Preview/Fixtures/Base.swift"],
             meant: "Sources/App/Features/Login/Preview/Fixtures/Base.swift")
    ]

    @Test("an edge ends on the candidate nearest by directory", arguments: picks, [false, true])
    func picksByDirectory(_ pick: Pick, reversed: Bool) {
        let candidates = reversed ? Array(pick.candidates.reversed()) : pick.candidates
        let index = pick.meant.flatMap(candidates.firstIndex(of:)) ?? 0
        #expect(subEdge(pick.writer, among: candidates) == [end(at: index)])
    }

    @Test("among those sharing the most, the first")
    func tieGoesToTheFirstOfTheNearest() {
        let candidates = ["Lib/X/Base.swift", "Pkg/A/Base.swift", "Pkg/B/Base.swift"]
        #expect(subEdge("Pkg/C/Sub.swift", among: candidates) == [end(at: 1)])
        #expect(subEdge("Pkg/C/Sub.swift", among: candidates.reversed()) == [end(at: 0)])
    }

    @Test("a writer with no file means the first")
    func writerWithNoFile() {
        #expect(subEdge(nil, among: ["PkgA/Base.swift", "PkgB/Base.swift"]) == [end(at: 0)])
    }

    @Test("a candidate with no file, or an empty one, shares nothing and never wins")
    func candidateWithNoFile() {
        #expect(subEdge("P/B/Sub.swift", among: [nil, "P/B/Base.swift"]) == [end(at: 1)])
        #expect(subEdge("P/B/Sub.swift", among: ["", "P/B/Base.swift"]) == [end(at: 1)])
        #expect(subEdge("P/B/Sub.swift", among: [nil, ""]) == [end(at: 0)])
    }

    // MARK: - The other tiers

    @Test("the writer's own file comes first, however near the others")
    func fileTierFirst() {
        let items = [
            declared(.class, "Base", in: "Pkg/Deep/Base.swift"),
            declared(.class, "Base", in: "Pkg/Deep/Sub.swift"),
            declared(.class, "Sub", in: "Pkg/Deep/Sub.swift", inheriting: ["Base"])
        ]
        #expect(edges(items) == [end(at: 1)])
    }

    @Test("the writer's module comes before any directory")
    func moduleTierFirst() {
        let items = [
            declared(.class, "Base", in: "Near/Base.swift", module: "Tool"),
            declared(.class, "Base", in: "Far/Base.swift", module: "Core"),
            declared(.class, "Sub", in: "Near/Sub.swift", module: "Core", inheriting: ["Base"])
        ]
        #expect(edges(items) == [end(at: 1)])
    }

    /// The file sees both modules' `Base`s, which Swift rejects or settles by a shadowing the
    /// lookup does not read. Where modules are known, that is not for a directory to decide, so
    /// `--package` output does not move.
    @Test("a writer of a known module never goes by directory, even with no candidate of its own",
          arguments: [false, true])
    func knownModuleKeepsTheFirst(reversed: Bool) throws {
        func parsed(_ source: String, module: String, in path: String) throws -> [SyntaxStructure] {
            let items = try #require(SyntaxStructure.create(from: source, module: module)?.substructure)
            items.forEach { $0.sourceLocation = SourceLocation(filePath: path, line: 1, column: 1) }
            return items
        }
        let far = try parsed("public class Base {}", module: "ModA", in: "Far/Base.swift")
        let near = try parsed("public class Base {}", module: "ModB", in: "Near/Base.swift")
        let writer = try parsed("import ModA\nimport ModB\nclass Sub: Base {}", module: "App", in: "Near/Sub.swift")
        #expect(edges((reversed ? near + far : far + near) + writer) == [end(at: 0)])
    }

    /// The module tier is what the rule stands in for: separate trees, it picks what modules do.
    @Test("packages in separate trees end an edge where their modules would", arguments: [false, true])
    func agreesWithTheModuleTier(reversed: Bool) {
        func items(withModules: Bool) -> [SyntaxStructure] {
            let bases = [
                declared(.class, "Base", in: "PkgA/Sources/A/Base.swift", module: withModules ? "A" : nil),
                declared(.class, "Base", in: "PkgB/Sources/B/Base.swift", module: withModules ? "B" : nil)
            ]
            return (reversed ? bases.reversed() : bases) + [
                declared(.class, "SubA", in: "PkgA/Sources/A/SubA.swift", module: withModules ? "A" : nil,
                         inheriting: ["Base"]),
                declared(.class, "SubB", in: "PkgB/Sources/B/SubB.swift", module: withModules ? "B" : nil,
                         inheriting: ["Base"])
            ]
        }
        #expect(edges(items(withModules: false)) == edges(items(withModules: true)))
    }
}
