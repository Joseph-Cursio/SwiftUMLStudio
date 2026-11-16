import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

/// In a target that enables `MemberImportVisibility` (SE-0444), a file sees the members another
/// module's extension adds only when it imports that module itself, directly, through an
/// `@_exported import`, or by a scoped import of one of its declarations. ModB adds a class `V`
/// to ModA's `Foo` and ModD a typealias `V`; in ModC, one file imports one of them and the writer
/// another. The lookup counted every module any file of ModC loads, so the edge could end on a
/// member the writer never sees (#201). Each case builds with swiftc, which resolves the member
/// only the expected supertype has; without the feature, the first fails: `V` is ambiguous. The
/// feature hides even the members of `Foo`'s own module, those of its body too, from a file that
/// reaches `Foo` without importing that module.
@Suite("A target with MemberImportVisibility reads only the members the writer's file imports")
struct MemberImportVisibilityTests {
    typealias File = ImportAwareRankTests.File
    typealias Case = ImportAwareRankTests.Case

    private static let bareFoo = File(module: "ModA", source: "public struct Foo {\n    public init() {}\n}\n")

    /// ModB's `V`, a class nested in `Foo`, spelling the extension `extendedAs`.
    private static func classAdded(as extendedAs: String) -> File {
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
    private static func aliasAdded(as extendedAs: String) -> File {
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

    /// ModE, which re-exports ModD.
    private static let reexporter = File(module: "ModE", source: "@_exported import ModD\n")

    /// A file of ModC that imports `module`, so ModC loads it.
    private static func holder(importing module: String) -> File {
        let thing = module == "ModB" ? "BThing" : "DThing"
        return File(module: "ModC", source: "import \(module)\n\nfunc holder() -> \(thing) { \(thing)() }\n")
    }

    /// ModC's `C`, written in a file whose imports after ModA's are `imports`.
    private static func writer(_ imports: String) -> File {
        File(module: "ModC", source: "import ModA\n\(imports)\n\nfinal class C: Foo.V {}\n")
    }

    private static func files(_ extended: String, _ rest: File...) -> [File] {
        [bareFoo, classAdded(as: extended), aliasAdded(as: extended), reexporter] + rest
    }

    /// A case of ModC, in a package whose extensions spell `Foo` as `extended`, where ModC enables
    /// `MemberImportVisibility` unless `enabled` is false.
    private static func readCase(
        _ name: String,
        extended: String,
        holding held: String,
        writerImports: String,
        member: String,
        hiddenLabel: String? = nil,
        enabled: Bool = true
    ) -> Case {
        Case(
            name: "extension \(extended): \(name)",
            files: files(extended, holder(importing: held), writer(writerImports)),
            member: member,
            hiddenLabel: hiddenLabel,
            memberImportVisibility: enabled ? ["ModC"] : []
        )
    }

    static let cases: [Case] = ["ModA.Foo", "Foo"].flatMap { extended in
        [
            readCase(
                "the alias the writer imports, not the class another file does",
                extended: extended, holding: "ModB", writerImports: "import ModD", member: "otherOnly"
            ),
            readCase(
                "the class the writer imports, not the alias another file does",
                extended: extended, holding: "ModD", writerImports: "import ModB", member: "vOnly",
                hiddenLabel: "Foo.V"
            ),
            readCase(
                "the alias the writer imports through a re-export",
                extended: extended, holding: "ModB", writerImports: "import ModE", member: "otherOnly"
            ),
            readCase(
                "the alias the writer imports a declaration of its module from",
                extended: extended, holding: "ModB", writerImports: "import class ModD.Other", member: "otherOnly"
            ),
            readCase(
                "without the feature, the alias another file's import loads",
                extended: extended, holding: "ModD", writerImports: "", member: "otherOnly", enabled: false
            ),
        ]
    }

    /// Where ModA declares `Foo`'s nested `V`.
    enum OwnPlacement: String, CaseIterable, Sendable {
        case body = "in Foo's body"
        case sameFile = "in an extension in Foo's file"
        case otherFile = "in an extension in another file of Foo's module"
    }

    /// ModA's files: `Foo`, a class, and its nested `V`, placed as `placement` says.
    private static func ownFoo(_ placement: OwnPlacement) -> [File] {
        let nested = "    open class V {\n        public init() {}\n        public func aOnly() {}\n    }\n"
        let foo = "open class Foo {\n    public init() {}\n"
        switch placement {
        case .body:
            return [File(module: "ModA", source: foo + nested + "}\n")]

        case .sameFile:
            return [File(module: "ModA", source: foo + "}\n\nextension Foo {\n" + nested + "}\n")]

        case .otherFile:
            return [
                File(module: "ModA", source: foo + "}\n"),
                File(module: "ModA", source: "extension Foo {\n" + nested + "}\n"),
            ]
        }
    }

    /// A `Foo.V` declared in ModA, against ModD's, for a writer that imports only ModD and reaches
    /// `Foo` through ModC's subclass `Sub` or its typealias `F`, declared in a file importing ModA.
    static let ownModuleCases: [Case] = OwnPlacement.allCases.flatMap { placement in
        [("subclass", "class Sub: Foo {}", "Sub.V"), ("typealias", "typealias F = Foo", "F.V")].map { reach in
            Case(
                name: "a V \(placement.rawValue) the writer does not import, through a \(reach.0)",
                files: ownFoo(placement) + [
                    aliasAdded(as: "Foo"),
                    File(module: "ModC", source: "import ModA\n\n\(reach.1)\n"),
                    File(module: "ModC", source: "import ModD\n\nfinal class C: \(reach.2) {}\n"),
                ],
                member: "otherOnly",
                hiddenLabel: nil,
                memberImportVisibility: ["ModC"]
            )
        }
    }

    /// Each case is read with its files in the order given and reversed, so no answer comes from
    /// which module's member is recorded first.
    @Test("a writer in such a target means the member its own file imports",
          arguments: cases + ownModuleCases, [false, true])
    func meansTheMemberTheFileImports(_ testCase: Case, reversed: Bool) throws {
        try ImportAwareRankTests.expectMeans(testCase, reversed: reversed)
    }

    /// Reading a package goes through its description, whose marked targets
    /// `declarations(inPackage:packageRoot:sdkPath:)` must pass on.
    @Test("a package's description marks the targets that enable the feature")
    func packageDescriptionMarksTargets() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var sourcesForModule: [String: [String]] = [:]
        let given = Self.files("ModA.Foo", Self.holder(importing: "ModB"), Self.writer("import ModD"))
        for (index, file) in given.enumerated() {
            let directory = root.appendingPathComponent("Sources/\(file.module)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("F\(index).swift")
            try file.source.write(to: url, atomically: true, encoding: .utf8)
            sourcesForModule[file.module, default: []].append("F\(index).swift")
        }
        func diagram(marking marked: Set<String>) throws -> [String] {
            let targets = sourcesForModule.keys.sorted().map { module in
                SPMTargetDescription(
                    name: module, kind: .library, path: "Sources/\(module)",
                    sources: sourcesForModule[module] ?? [], dependencies: [],
                    enablesMemberImportVisibility: marked.contains(module)
                )
            }
            let items = SyntaxStructure.declarations(
                inPackage: SPMPackageDescription(name: "Probe", targets: targets), packageRoot: root, sdkPath: nil
            )
            let graph = LayoutGraphBuilder.buildClassDiagram(
                from: items, configuration: Configuration(elements: ElementOptions(showExtensions: .all), format: .svg)
            )
            let other = try #require(graph.owner(of: "otherOnly"))
            let ends = graph.edgeEnds.filter { $0.hasPrefix("C -> ") }
            return ends.map { $0 == "C -> \(other)" ? "Other" : $0 }
        }
        #expect(try diagram(marking: ["ModC"]) == ["Other"])
        #expect(try diagram(marking: []) != ["Other"])
    }
}
