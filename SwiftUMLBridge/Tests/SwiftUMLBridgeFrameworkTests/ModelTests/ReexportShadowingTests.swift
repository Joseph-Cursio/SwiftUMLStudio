import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// A module's own type shadows a same-named one of a module it re-exports (#200): in a file that
/// imports ModX, which has `@_exported import ModA` and its own `Base`, `Base` is ModX's. Each
/// case was built as a package with `swift build`, and calling the member only the other `Base`
/// has failed with `has no member`.
@Suite("A module's own type shadows a same-named type it re-exports")
struct ReexportShadowingTests {

    typealias File = ImportAwareRankTests.File
    typealias Case = ImportAwareRankTests.Case

    private static func base(_ module: String, _ member: String, access: String = "open") -> File {
        File(module: module,
             source: "\(access) class Base {\n    public init() {}\n    public func \(member)() {}\n}\n")
    }

    private static func reexporter(_ module: String, of reexported: String, _ member: String) -> File {
        File(module: module, source: "@_exported import \(reexported)\n\n" + base(module, member).source)
    }

    private static func writer(_ imports: String, _ supertype: String = "Base") -> File {
        File(module: "ModC", source: imports + "\nfinal class C: \(supertype) {}\n")
    }

    private static func fooWithV(_ module: String, _ member: String, reexporting reexported: String? = nil) -> File {
        File(module: module, source: (reexported.map { "@_exported import \($0)\n\n" } ?? "") + """
            public struct Foo {
                public init() {}
                open class V {
                    public init() {}
                    public func \(member)() {}
                }
            }
            """)
    }

    private static func aliasedBase(_ module: String, _ member: String, reexporting reexported: String? = nil) -> File {
        let target = "R\(module)"
        return File(module: module, source: (reexported.map { "@_exported import \($0)\n\n" } ?? "") + """
            open class \(target) {
                public init() {}
                public func \(member)() {}
            }

            public typealias Base = \(target)
            """)
    }

    static let cases: [Case] = [
        Case(name: "a file that imports the re-exporter means its own type", files: [
            base("ModA", "aOnly"), reexporter("ModX", of: "ModA", "xOnly"), writer("import ModX\n")
        ], member: "xOnly", hiddenLabel: nil),
        Case(name: "the re-exported module sorting after the re-exporter changes nothing", files: [
            base("ModZ", "zOnly"), reexporter("ModX", of: "ModZ", "xOnly"), writer("import ModX\n")
        ], member: "xOnly", hiddenLabel: nil),
        Case(name: "a file that imports only the re-exported module means its type", files: [
            base("ModA", "aOnly"), reexporter("ModX", of: "ModA", "xOnly"), writer("import ModA\n")
        ], member: "aOnly", hiddenLabel: nil),
        Case(name: "an internal type of the re-exporter shadows nothing", files: [
            base("ModA", "aOnly"),
            File(module: "ModX", source: "@_exported import ModA\n\n" + base("ModX", "xOnly", access: "").source),
            writer("import ModX\n")
        ], member: "aOnly", hiddenLabel: nil),
        Case(name: "an @_spi type of the re-exporter shadows nothing for a file without an @_spi import", files: [
            base("ModA", "aOnly"),
            File(module: "ModX",
                 source: "@_exported import ModA\n\n" + base("ModX", "xOnly", access: "@_spi(Ex) open").source),
            writer("import ModX\n")
        ], member: "aOnly", hiddenLabel: nil),
        Case(name: "a type of the re-exporter marked @_spi under an #if still shadows", files: [
            base("ModA", "aOnly"),
            File(module: "ModX", source: "@_exported import ModA\n\n#if os(Linux)\n@_spi(Ex)\n#endif\n"
                 + base("ModX", "xOnly").source),
            writer("import ModX\n")
        ], member: "xOnly", hiddenLabel: nil),
        Case(name: "a type of the re-exporter unavailable on another platform still shadows", files: [
            base("ModA", "aOnly"),
            File(module: "ModX", source: "@_exported import ModA\n\n@available(iOS, unavailable)\n"
                 + base("ModX", "xOnly").source),
            writer("import ModX\n")
        ], member: "xOnly", hiddenLabel: nil),
        Case(name: "a type of the re-exporter obsoleted in a later version still shadows", files: [
            base("ModA", "aOnly"),
            File(module: "ModX", source: "@_exported import ModA\n\n"
                 + "@available(macOS, introduced: 10.15, obsoleted: 99)\n" + base("ModX", "xOnly").source),
            writer("import ModX\n")
        ], member: "xOnly", hiddenLabel: nil),
        Case(name: "an @_spi type of the re-exporter shadows for a file that imports it with @_spi", files: [
            base("ModA", "aOnly"),
            File(module: "ModX",
                 source: "@_exported import ModA\n\n" + base("ModX", "xOnly", access: "@_spi(Ex) open").source),
            writer("@_spi(Ex) import ModX\n")
        ], member: "xOnly", hiddenLabel: nil),
        Case(name: "a scoped import of the re-exported type still names it", files: [
            base("ModA", "aOnly"), reexporter("ModX", of: "ModA", "xOnly"),
            writer("import ModX\nimport class ModA.Base\n")
        ], member: "aOnly", hiddenLabel: nil),
        Case(name: "through a chain of re-exports, the nearest declaring module's type", files: [
            base("ModA", "aOnly"), reexporter("ModX", of: "ModA", "xOnly"),
            File(module: "Top", source: "@_exported import ModX\n"), writer("import Top\n")
        ], member: "xOnly", hiddenLabel: nil),
        Case(name: "through a chain where each module declares the type, the outermost's", files: [
            base("ModA", "aOnly"), reexporter("ModX", of: "ModA", "xOnly"), reexporter("Top", of: "ModX", "topOnly"),
            writer("import Top\n")
        ], member: "topOnly", hiddenLabel: nil),
        Case(name: "the first component of a dotted name is the re-exporter's type", files: [
            fooWithV("ModA", "aOnly"), fooWithV("ModX", "xOnly", reexporting: "ModA"), writer("import ModX\n", "Foo.V")
        ], member: "xOnly", hiddenLabel: "Foo.V"),
        Case(name: "the writer's own module's type, where it re-exports the other", files: [
            base("ModA", "aOnly"), reexporter("ModC", of: "ModA", "cOnly"), writer("import ModA\n")
        ], member: "cOnly", hiddenLabel: nil),
        Case(name: "a typealias of the re-exporter shadows one of the re-exported module", files: [
            aliasedBase("ModA", "aOnly"), aliasedBase("ModX", "xOnly", reexporting: "ModA"), writer("import ModX\n")
        ], member: "xOnly", hiddenLabel: nil)
    ]

    /// Each case is read with its files in the order given and reversed, so no answer comes from
    /// which module's type is recorded first.
    @Test("a name means the re-exporter's own type", arguments: cases, [false, true])
    func meansTheReexportersType(_ testCase: Case, reversed: Bool) throws {
        try ImportAwareRankTests.expectMeans(testCase, reversed: reversed)
    }

    /// A build may drop a type under an `#if`, so one the re-exporter declares there shadows
    /// nothing, and the name is ranked as it was before re-exports were read: here, by read order,
    /// with the re-exported module's `Base` read first. On macOS Swift means that one.
    @Test("a type of the re-exporter under an #if shadows nothing")
    func conditionalReexporterType() throws {
        let testCase = Case(name: "conditional", files: [
            Self.base("ModA", "aOnly"),
            File(module: "ModX",
                 source: "@_exported import ModA\n\n#if os(Linux)\n" + Self.base("ModX", "xOnly").source + "#endif\n"),
            Self.writer("import ModX\n")
        ], member: "aOnly", hiddenLabel: nil)
        try ImportAwareRankTests.expectMeans(testCase, reversed: false)
    }
}
