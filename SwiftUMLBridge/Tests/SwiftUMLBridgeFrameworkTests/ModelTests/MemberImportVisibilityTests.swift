import Testing

/// In a target that enables `MemberImportVisibility` (SE-0444), a file sees the members another
/// module's extension adds only when it imports that module itself, directly, through an
/// `@_exported import`, or by a scoped import of one of its declarations. ModB adds a class `V`
/// to ModA's `Foo` and ModD a typealias `V`; in ModC, one file imports one of them and the writer
/// another. The lookup counted every module any file of ModC loads, so the edge could end on a
/// member the writer never sees (#201). Each case builds with swiftc, which resolves the member
/// only the expected supertype has; without the feature, the first fails: `V` is ambiguous.
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

    /// Each case is read with its files in the order given and reversed, so no answer comes from
    /// which module's member is recorded first.
    @Test("a writer in such a target means the member its own file imports", arguments: cases, [false, true])
    func meansTheMemberTheFileImports(_ testCase: Case, reversed: Bool) throws {
        try ImportAwareRankTests.expectMeans(testCase, reversed: reversed)
    }
}
