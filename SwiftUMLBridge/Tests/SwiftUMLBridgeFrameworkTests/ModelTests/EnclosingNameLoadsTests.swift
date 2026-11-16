@testable import SwiftUMLBridgeFramework
import Testing

/// A type written bare inside an extension of the type it is a member of, `V` in
/// `extension Foo { final class C: V {} }`, means the member of that type the writer sees, as the
/// dotted `Foo.V` does: an extension's in a module the writer's module loads, or in a target that
/// enables `MemberImportVisibility` (SE-0444), one its own file imports. ModB adds a class `V` to
/// ModA's `Foo` and ModD a typealias `V`; in ModC, one file imports one of them and the writer
/// another. The bare name was looked up among every same-named member, whichever module added it,
/// and was not found when the member meant was recorded only under `ModA.Foo`, as an extension
/// spelling the type that way records it, while the writer's extension spelled it `Foo`. Each case builds
/// with swiftc, which resolves the member only the expected supertype has.
@Suite("A bare name in an extension means the member of its type the writer sees")
struct EnclosingNameLoadsTests {
    typealias File = ImportAwareRankTests.File

    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let files: [File]
        /// A member only the box `C` inherits from lists.
        let member: String
        /// The PlantUML line of `C`'s edge.
        let line: String
        /// The modules that enable `MemberImportVisibility` (#201).
        let memberImportVisibility: Set<String>

        var testDescription: String { name }
    }

    static let bareFoo = File(module: "ModA", source: "public struct Foo {\n    public init() {}\n}\n")

    /// ModB's `V`, a class nested in `Foo`, spelling the extension `extendedAs`.
    static func classAdded(as extendedAs: String) -> File {
        File(module: "ModB", source: """
            import ModA

            extension \(extendedAs) {
                open class V {
                    public init() {}
                    public func vOnly() {}
                }
            }

            public struct BThing {
                public init() {}
            }
            """)
    }

    /// ModD's `V`, a typealias of its top-level `Other`, spelling the extension `extendedAs`.
    static func aliasAdded(as extendedAs: String) -> File {
        File(module: "ModD", source: """
            import ModA

            extension \(extendedAs) {
                public typealias V = Other
            }

            open class Other {
                public init() {}
                public func otherOnly() {}
            }

            public struct DThing {
                public init() {}
            }
            """)
    }

    /// A file of ModC that imports `module`, so ModC loads it.
    static func holder(importing module: String) -> File {
        let thing = module == "ModB" ? "BThing" : "DThing"
        return File(module: "ModC", source: "import \(module)\n\nfunc holder() -> \(thing) { \(thing)() }\n")
    }

    /// ModC's `C`, nested in an extension that spells `Foo` as `writerExtends`, in a file that
    /// imports ModA and `module`; with `inStruct`, nested in a struct `S` of that extension, so
    /// the name is looked for in `S` first.
    private static func writer(extending writerExtends: String, importing module: String, inStruct: Bool) -> File {
        let declaration = inStruct
            ? "    struct S {\n        final class C: V {}\n    }\n"
            : "    final class C: V {}\n"
        let source = "import ModA\nimport \(module)\n\nextension \(writerExtends) {\n\(declaration)}\n"
        return File(module: "ModC", source: source)
    }

    /// Where `C` is, and which module's member it means, in a package whose ModB spells `Foo` as
    /// `classExtended`, whose ModD spells it `aliasExtended`, and whose writer's extension spells
    /// it `writerExtends`.
    private struct Setup {
        let classExtended: String
        let aliasExtended: String
        let writerExtends: String
        var inStruct = false

        /// A case where ModC enables `MemberImportVisibility` when `enabled` is true, with a
        /// holder file importing `held`, if any, and the writer importing `imported`.
        func readCase(_ name: String, held: String?, imported: String, enabled: Bool) -> Case {
            let means = imported == "ModD" ? "Other" : (classExtended == "ModA.Foo" ? "ModA.Foo.V" : "Foo.V")
            let qualifier = writerExtends == "ModA.Foo" ? "ModA." : ""
            let writerId = qualifier + (inStruct ? "Foo.S.C" : "Foo.C")
            let files = [bareFoo, classAdded(as: classExtended), aliasAdded(as: aliasExtended)]
                + (held.map { [holder(importing: $0)] } ?? [])
                + [writer(extending: writerExtends, importing: imported, inStruct: inStruct)]
            let place = inStruct ? "struct in extension \(writerExtends)" : "extension \(writerExtends)"
            let extended = classExtended == aliasExtended
                ? "extension \(classExtended)" : "ModB's extension \(classExtended), ModD's \(aliasExtended)"
            return Case(
                name: "\(extended), writer in \(place): \(name)",
                files: files,
                member: imported == "ModD" ? "otherOnly" : "vOnly",
                line: "\(means) <|-- \(writerId) : inherits",
                memberImportVisibility: enabled ? ["ModC"] : []
            )
        }

        var cases: [Case] {
            [
                readCase(
                    "with the feature, the alias the writer imports, not the class another file does",
                    held: "ModB", imported: "ModD", enabled: true
                ),
                readCase(
                    "without the feature, the alias, as no file loads the class",
                    held: nil, imported: "ModD", enabled: false
                ),
                readCase(
                    "without the feature, the class, as no file loads the alias",
                    held: nil, imported: "ModB", enabled: false
                ),
                readCase(
                    "with the feature, the class the writer imports, not the alias another file does",
                    held: "ModD", imported: "ModB", enabled: true
                ),
            ]
        }
    }

    static let spellings = ["ModA.Foo", "Foo"]

    /// Each spelling of ModB's, ModD's and the writer's extensions. Where ModB and ModD spell
    /// `Foo` apart, the member the writer does not see may be the only one recorded under the
    /// writer's spelling; it does not stop the name, which finds the other (`moduleMatch`).
    static let cases: [Case] = spellings.flatMap { classExtended in
        spellings.flatMap { aliasExtended in
            ["Foo", "ModA.Foo"].flatMap { writerExtends in
                Setup(classExtended: classExtended, aliasExtended: aliasExtended, writerExtends: writerExtends)
                    .cases
            }
        }
    }

    /// The name is looked for in the struct around `C` first, which has no `V`, then in `Foo`.
    static let inStructCases: [Case] = spellings.flatMap { extended in
        Setup(classExtended: extended, aliasExtended: extended, writerExtends: "Foo", inStruct: true).cases
    }

    /// Each case is read with its files in the order given and reversed, so no answer comes from
    /// which module's member is recorded first.
    @Test("a bare name in an extension means the member its writer sees",
          arguments: cases + inStructCases, [false, true])
    func meansTheMemberTheWriterSees(_ testCase: Case, reversed: Bool) throws {
        try Self.expectMeans(testCase, reversed: reversed)
    }

    @Test("a bare name means what swiftc resolves it to in hand-built packages",
          arguments: builtCases, [false, true])
    func meansWhatSwiftcResolves(_ testCase: Case, reversed: Bool) throws {
        try Self.expectMeans(testCase, reversed: reversed)
    }

    /// `testCase`'s `C` inherits from the box listing its member, in both extension modes, and its
    /// PlantUML edge is its line.
    private static func expectMeans(_ testCase: Case, reversed: Bool) throws {
        let given = testCase.files.map { (module: Optional($0.module), source: $0.source) }
        let files = reversed ? given.reversed() : given
        let items = { try moduleQualifiedItems(files, memberImportVisibility: testCase.memberImportVisibility) }
        for mode in [ExtensionVisualization.all, .merged] {
            let graph = LayoutGraphBuilder.buildClassDiagram(
                from: try items(),
                configuration: Configuration(elements: ElementOptions(showExtensions: mode), format: .svg)
            )
            let meant = try #require(graph.owner(of: testCase.member), "\(mode)")
            let writerId = String(testCase.line.split(separator: " ")[2])
            #expect(graph.edgeEnds.filter { $0.hasPrefix("\(writerId) -> ") } == ["\(writerId) -> \(meant)"], "\(mode)")

            let script = DiagramScript(
                items: try items(), configuration: Configuration(elements: ElementOptions(showExtensions: mode))
            )
            #expect(ClassDiagramIds.lines(of: script.text, containing: "<|-- \(writerId) ") == [testCase.line],
                    "\(mode)")
        }
    }
}
