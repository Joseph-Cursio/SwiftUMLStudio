import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// An available type shadows a same-named `@available(..., unavailable)` one of another module
/// (#200): in a file that imports ModA, whose `Base` is a stub left by a rename, and ModB, `Base`
/// is ModB's. Each case was built as a package with `swift build`, and calling the member only
/// the other `Base` has failed with `has no member`. Where Swift picks an unavailable `Base` by
/// an earlier rule, the build fails with `'Base' is unavailable`, naming that declaration. A
/// re-exporter's unavailable `Base` is that only for a file that reaches the re-exported module
/// through it alone, which does not build, so the diagram lets it shadow nothing.
@Suite("An available type shadows an unavailable one of another module")
struct AvailabilityShadowingTests {

    typealias File = ImportAwareRankTests.File
    typealias Case = ImportAwareRankTests.Case

    private static func base(_ module: String, _ member: String, marked attribute: String = "") -> File {
        File(module: module, source: attribute + """
            open class Base {
                public init() {}
                public func \(member)() {}
            }

            """)
    }

    private static let stub = "@available(*, unavailable, renamed: \"NewBase\")\n"
    private static let unavailable = "@available(*, unavailable)\n"

    private static func writer(_ imports: String) -> File {
        File(module: "ModC", source: imports + "\nfinal class C: Base {}\n")
    }

    static let cases: [Case] = [
        Case(name: "a renamed stub is shadowed", files: [
            base("ModA", "aOnly", marked: stub), base("ModB", "bOnly"), writer("import ModA\nimport ModB\n")
        ], member: "bOnly", hiddenLabel: nil),
        Case(name: "an unavailable type of a module sorting last is shadowed", files: [
            base("ModZ", "zOnly", marked: unavailable), base("ModB", "bOnly"), writer("import ModB\nimport ModZ\n")
        ], member: "bOnly", hiddenLabel: nil),
        Case(name: "an unavailable typealias is shadowed", files: [
            File(module: "ModA", source: """
                open class NewBase {
                    public init() {}
                    public func aOnly() {}
                }

                \(stub)public typealias Base = NewBase
                """),
            File(module: "ModB", source: """
                open class RB {
                    public init() {}
                    public func bOnly() {}
                }

                public typealias Base = RB
                """),
            writer("import ModA\nimport ModB\n")
        ], member: "bOnly", hiddenLabel: nil),
        Case(name: "a type unavailable on the platform built for is shadowed", files: [
            base("ModA", "aOnly", marked: "@available(macOS, unavailable)\n"), base("ModB", "bOnly"),
            writer("import ModA\nimport ModB\n")
        ], member: "bOnly", hiddenLabel: nil),
        Case(name: "a type marked unavailable under an #if is shadowed", files: [
            base("ModA", "aOnly", marked: "#if os(macOS)\n@available(*, unavailable)\n#endif\n"),
            base("ModB", "bOnly"), writer("import ModA\nimport ModB\n")
        ], member: "bOnly", hiddenLabel: nil),
        Case(name: "the writer's module's own unavailable type shadows an imported one", files: [
            base("ModA", "aOnly"), File(module: "ModC", source: base("ModC", "cOnly", marked: unavailable).source),
            writer("import ModA\n")
        ], member: "cOnly", hiddenLabel: nil),
        Case(name: "the writer's module's own type shadows an unavailable imported one", files: [
            base("ModA", "aOnly", marked: unavailable), File(module: "ModC", source: base("ModC", "cOnly").source),
            writer("import ModA\n")
        ], member: "cOnly", hiddenLabel: nil),
        Case(name: "a re-exporter's unavailable type shadows nothing the file reaches another way", files: [
            base("ModA", "aOnly"),
            File(module: "ModX",
                 source: "@_exported import ModA\n\n" + base("ModX", "xOnly", marked: unavailable).source),
            writer("import ModX\nimport ModA\n")
        ], member: "aOnly", hiddenLabel: nil),
        Case(name: "a re-exporter's unavailable type shadows nothing another re-exporter shows", files: [
            base("ModA", "aOnly"),
            File(module: "ModX",
                 source: "@_exported import ModA\n\n" + base("ModX", "xOnly", marked: unavailable).source),
            File(module: "ModY", source: "@_exported import ModA\n\npublic struct YThing {}\n"),
            writer("import ModX\nimport ModY\n")
        ], member: "aOnly", hiddenLabel: nil),
        Case(name: "a re-exporter's type shadows an unavailable re-exported one", files: [
            base("ModA", "aOnly", marked: unavailable),
            File(module: "ModX", source: "@_exported import ModA\n\n" + base("ModX", "xOnly").source),
            writer("import ModX\n")
        ], member: "xOnly", hiddenLabel: nil),
        Case(name: "a scoped import's unavailable type shadows a whole module's", files: [
            base("ModA", "aOnly"), base("ModB", "bOnly", marked: unavailable),
            writer("import ModA\nimport class ModB.Base\n")
        ], member: "bOnly", hiddenLabel: nil),
        Case(name: "a scoped import's type shadows a whole module's unavailable one", files: [
            base("ModA", "aOnly", marked: unavailable), base("ModB", "bOnly"),
            writer("import ModA\nimport class ModB.Base\n")
        ], member: "bOnly", hiddenLabel: nil)
    ]

    /// Each case is read with its files in the order given and reversed, so no answer comes from
    /// which module's type is recorded first.
    @Test("a name means the type Swift picks among available and unavailable ones", arguments: cases, [false, true])
    func meansTheAvailableType(_ testCase: Case, reversed: Bool) throws {
        try ImportAwareRankTests.expectMeans(testCase, reversed: reversed)
    }

    @Test("an @available that says unavailable marks the declaration, and no other",
          arguments: [
            ("@available(*, unavailable)", true),
            ("@available(*, unavailable, renamed: \"NewBase\")", true),
            ("@available(macOS, unavailable)", true),
            ("@available(iOS, unavailable, message: \"use NewBase\")", true),
            ("#if os(macOS)\n@available(*, unavailable)\n#endif", true),
            ("@available(*, deprecated)", false),
            ("@available(*, deprecated, message: \"unavailable\")", false),
            ("@available(macOS 14, *)", false),
            ("@available(macOS, introduced: 10.15, obsoleted: 11)", false),
            ("@MainActor", false)
          ])
    func parsed(attribute: String, isUnavailable: Bool) throws {
        let source = "\(attribute)\npublic struct Base {}\n"
        let item = try #require(SyntaxStructure.create(from: source)?.substructure?.first)
        #expect(item.isUnavailable == isUnavailable)
    }
}
