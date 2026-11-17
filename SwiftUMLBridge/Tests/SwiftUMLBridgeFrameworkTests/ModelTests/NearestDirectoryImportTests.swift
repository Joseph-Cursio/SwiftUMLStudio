import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

private typealias Fixture = NearestDirectoryFixture

/// Of same-named types equally near a writer of no known module, the one under a directory named
/// for a module the writer's file imports, in either read order (#233). Only a SwiftPM target's
/// directory counts, and only when each tied candidate's lies past what it shares with the writer.
@Suite("Without modules, an import breaks a tie by directory")
struct NearestDirectoryImportTests {

    struct Case: CustomTestStringConvertible, Sendable {
        let label: String
        /// Each declares `class Base`, in this order and then reversed.
        let candidates: [String]
        let writer: String
        let imports: [String]
        /// The candidate `Sub: Base` means; `nil` for the first read, in each order.
        let meant: String?
        var testDescription: String { label }
    }

    static let cases: [Case] = [
        Case(
            label: "the imported target's",
            candidates: ["/r/Sources/ModA/A.swift", "/r/Sources/ModB/B.swift"],
            writer: "/r/Sources/ModC/C.swift",
            imports: ["ModB"], meant: "/r/Sources/ModB/B.swift"
        ),
        Case(
            label: "from a folder inside the target",
            candidates: ["/r/Sources/ModA/Models/A.swift", "/r/Sources/ModB/Models/B.swift"],
            writer: "/r/Sources/ModC/C.swift",
            imports: ["Foundation", "ModB"], meant: "/r/Sources/ModB/Models/B.swift"
        ),
        Case(
            label: "of packages scanned together, by the directory after Sources",
            candidates: ["/co/pkg-a/Sources/ModA/A.swift", "/co/pkg-b/Sources/ModB/B.swift"],
            writer: "/co/app/Sources/App/C.swift",
            imports: ["ModB"], meant: "/co/pkg-b/Sources/ModB/B.swift"
        ),
        Case(
            label: "by the directory after the last Sources, under a src of one's own",
            candidates: ["/Users/me/src/pkg-a/Sources/ModA/A.swift", "/Users/me/src/pkg-b/Sources/ModB/B.swift"],
            writer: "/Users/me/src/app/Sources/App/C.swift",
            imports: ["ModB"], meant: "/Users/me/src/pkg-b/Sources/ModB/B.swift"
        ),
        Case(
            label: "a target's directory as Swift names it",
            candidates: ["/r/Sources/my-lib/A.swift", "/r/Sources/other/B.swift"],
            writer: "/r/Sources/App/C.swift",
            imports: ["my_lib"], meant: "/r/Sources/my-lib/A.swift"
        ),
        Case(
            label: "on relative paths",
            candidates: ["Sources/ModA/A.swift", "Sources/ModB/B.swift"],
            writer: "Sources/ModC/C.swift",
            imports: ["ModB"], meant: "Sources/ModB/B.swift"
        ),
        Case(
            label: "not a folder deeper in another target named like an SDK module",
            candidates: ["/r/Sources/Networking/N.swift", "/r/Sources/ModZ/Foundation/Z.swift"],
            writer: "/r/Sources/App/C.swift",
            imports: ["Foundation", "Net"], meant: nil
        ),
        Case(
            label: "not a folder of the writer's own target named like an SDK module",
            candidates: ["/r/Sources/ModZ/Mobile/B.swift", "/r/Sources/ModZ/Foundation/B.swift"],
            writer: "/r/Sources/ModZ/Views/V.swift",
            imports: ["Foundation"], meant: nil
        ),
        Case(
            label: "not outside SwiftPM's layout, as an Xcode project's Shared folder",
            candidates: ["/r/Shared/Base.swift", "/r/Packages/ModB/Sources/ModB/Base.swift"],
            writer: "/r/iOS/C.swift",
            imports: ["ModB"], meant: nil
        ),
        Case(
            label: "not a folder named like an SDK module under an Xcode target's Source",
            candidates: ["/r/DesignKit/Source/Core/Theme.swift", "/r/MyApp/Source/UIKit/Theme.swift"],
            writer: "/r/WidgetExt/W.swift",
            imports: ["UIKit", "DesignKit"], meant: nil
        ),
        Case(
            label: "not a folder named like an SDK module under a Tuist project's Sources",
            candidates: [
                "/r/Projects/Feature/Sources/Models/Base.swift", "/r/Projects/Core/Sources/Foundation/Base.swift",
            ],
            writer: "/r/Projects/App/Sources/V.swift",
            imports: ["Foundation", "Feature"], meant: nil
        ),
        Case(
            label: "not folders right under a shared src beside a package's target",
            candidates: ["/r/src/Shared/Base.swift", "/r/src/Packages/ModB/Sources/ModB/Base.swift"],
            writer: "/r/src/iOS/C.swift",
            imports: ["ModB"], meant: nil
        ),
        Case(
            label: "a target spelled decomposed in its path, imported composed",
            candidates: ["/r/Sources/Other/B.swift", "/r/Sources/Cafe\u{301}/A.swift"],
            writer: "/r/Sources/App/C.swift",
            imports: ["Caf\u{E9}"], meant: "/r/Sources/Cafe\u{301}/A.swift"
        ),
        Case(
            label: "never over a nearer directory",
            candidates: ["/r/Sources/Foo/Base.swift", "/r/Tests/BarTests/Base.swift"],
            writer: "/r/Tests/FooTests/T.swift",
            imports: ["Foo"], meant: "/r/Tests/BarTests/Base.swift"
        ),
        Case(
            label: "not in the writer's own directory",
            candidates: ["/r/Sources/ModC/Inner/A.swift", "/r/Sources/ModC/ModB/B.swift"],
            writer: "/r/Sources/ModC/C.swift",
            imports: ["ModB"], meant: nil
        ),
        Case(
            label: "not stopped by a scoped import of an untied target",
            candidates: ["/r/Sources/ModA/A.swift", "/r/Sources/ModB/B.swift"],
            writer: "/r/Sources/ModC/C.swift",
            imports: ["class ModX.Other", "ModB"], meant: "/r/Sources/ModB/B.swift"
        ),
        Case(
            label: "known first read: a scoped import of a tied target, which shadows a whole one for its name alone",
            candidates: ["/r/Sources/ModA/A.swift", "/r/Sources/ModB/B.swift"],
            writer: "/r/Sources/ModC/C.swift",
            imports: ["ModA", "class ModB.Base"], meant: nil
        ),
        Case(
            label: "not when both are imported",
            candidates: ["/r/Sources/ModA/A.swift", "/r/Sources/ModB/B.swift"],
            writer: "/r/Sources/ModC/C.swift",
            imports: ["ModA", "ModB"], meant: nil
        ),
    ]

    @Test("a tie goes to the type under a directory the writer imports", arguments: cases, [false, true])
    func tieGoesToImport(_ tie: Case, reversed: Bool) throws {
        let candidates = reversed ? tie.candidates.reversed() : tie.candidates
        let imports = tie.imports.map { "import \($0)\n" }.joined()
        let files: [Fixture.File] = candidates.map { ($0, "public class Base {}") }
            + [(tie.writer, "\(imports)class Sub: Base {}")]
        let index = tie.meant.flatMap { candidates.firstIndex(of: $0) } ?? 0
        #expect(try Fixture.edges(files) == [index == 0 ? "Sub -> Base" : "Sub -> Base_\(index)"])
        let alias = index == 0 ? "Base" : "Base\(index - 1)"
        #expect(try Fixture.lines(files, .plantuml).contains("\(alias) <|-- Sub : inherits"))
    }

    /// Another module sees only what its target declares `public`, `open` or `package`, so an
    /// internal `Base` of the imported ModB is not the one meant: the first read stands.
    @Test("not an imported target's type other modules cannot see", arguments: [false, true])
    func notInternalOfImport(reversed: Bool) throws {
        let candidates: [Fixture.File] = [
            ("/r/Sources/Networking/Base.swift", "open class Base {}"), ("/r/Sources/ModB/Base.swift", "class Base {}"),
        ]
        let files = (reversed ? candidates.reversed() : candidates)
            + [("/r/Sources/ModC/C.swift", "import Net\nimport ModB\nclass Sub: Base {}")]
        #expect(try Fixture.edges(files) == ["Sub -> Base"])
    }

    /// A `@testable` import shows the module's `internal` types too, as a test target's files
    /// see them.
    @Test("an internal type of a target imported with @testable", arguments: [false, true])
    func internalOfTestableImport(reversed: Bool) throws {
        let candidates: [Fixture.File] = [
            ("/r/Sources/ModA/Base.swift", "class Base {}"), ("/r/Sources/ModB/Base.swift", "class Base {}"),
        ]
        let ordered = reversed ? candidates.reversed() : candidates
        let files = ordered + [("/r/Tests/ModBTests/T.swift", "@testable import ModB\nclass Sub: Base {}")]
        let index = reversed ? 0 : 1
        #expect(try Fixture.edges(files) == [index == 0 ? "Sub -> Base" : "Sub -> Base_1"])
    }

    /// An import outranks the kinds' order, protocols first: ModB's class, not ModA's protocol.
    @Test("an imported class over an equally near protocol", arguments: [false, true])
    func importOverProtocol(reversed: Bool) throws {
        let candidates: [Fixture.File] = [
            ("/r/Sources/ModA/A.swift", "public protocol Base {}"),
            ("/r/Sources/ModB/B.swift", "open class Base {}"),
        ]
        let files = (reversed ? candidates.reversed() : candidates)
            + [("/r/Sources/ModC/C.swift", "import ModB\nclass Sub: Base {}")]
        let lines = try Fixture.lines(files, .plantuml)
        #expect(lines.contains { $0.hasSuffix("<|-- Sub : inherits") })
        #expect(!lines.contains { $0.contains("<|.. Sub") })
    }

    /// Sequence diagrams follow a typealias as class diagrams do, with the file's imports (#233).
    @Test("a call through a typealias ends on the imported target's type", arguments: [false, true])
    func callThroughAlias(reversed: Bool) throws {
        let modules: [(file: URL, contents: String)] = [
            (URL(fileURLWithPath: "/r/Sources/ModA/A.swift"),
             "public struct AImpl { public static func make() {} }\npublic typealias Svc = AImpl"),
            (URL(fileURLWithPath: "/r/Sources/ModB/B.swift"),
             "open class BImpl { public static func make() {} }\npublic typealias Svc = BImpl"),
        ]
        let caller = (file: URL(fileURLWithPath: "/r/Sources/ModC/C.swift"),
                      contents: "import ModB\nstruct Caller {\n    func run() { Svc.make() }\n}")
        let sources = (reversed ? modules.reversed() : modules) + [caller]
        let aliases = TypeAliasResolver(sources: sources)
        let edges = CallGraphExtractor.extract(from: caller.contents, file: caller.file, aliases: aliases).edges
        #expect(edges.map { "\($0.calleeType ?? "?").\($0.calleeMethod)" } == ["BImpl.make"])
    }
}
