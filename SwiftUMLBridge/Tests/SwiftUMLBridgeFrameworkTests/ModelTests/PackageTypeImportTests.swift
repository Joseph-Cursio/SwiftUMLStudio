import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

/// `deps --types --package` tagged a supertype with the first target that declares its name,
/// whatever the writer's file imports, so where ModA and ModB each declare `open class Base` and
/// ModC's file imports only ModB, `final class C: Base {}` was drawn to `Base <<ModA>>` (#202).
/// The class diagram ends that edge on ModB's `Base`, as Swift does. Each end is now tagged with
/// the module of the declaration the class diagram ends it on. Every case builds with swiftc,
/// which resolves the member only the expected `Base` has.
@Suite("deps --types --package tags a supertype with the module the writer's file means")
struct PackageTypeImportTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let writer: String
        var reexporter = "public struct EThing {}"
        /// More of ModA's source, after its `Base` and `Proto`.
        var moreOfModA = ""
        /// More of ModB's source, after its `Base` and `Proto`.
        var moreOfModB = ""
        /// The PlantUML node line that must appear, or `nil` where the type must be untagged.
        let node: String?
        /// A type whose node must carry no tag, so no `class` line names it.
        var untagged: String?

        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(
            name: "the file imports only ModB", writer: "import ModB\n\nfinal class C: Base {}",
            node: "class \"Base\" as Base <<ModB>>"
        ),
        Case(
            name: "the file imports only ModA", writer: "import ModA\n\nfinal class C: Base {}",
            node: "class \"Base\" as Base <<ModA>>"
        ),
        Case(
            name: "the file imports both and qualifies the name with ModB",
            writer: "import ModA\nimport ModB\n\nfinal class C: ModB.Base {}",
            node: "class \"ModB.Base\" as ModB.Base <<ModB>>"
        ),
        Case(
            name: "the file reaches ModB's Base through its own typealias",
            writer: "import ModB\n\ntypealias Parent = Base\nfinal class C: Parent {}",
            node: "class \"Base\" as Base <<ModB>>"
        ),
        Case(
            name: "the file extends Base, which is ModB's",
            writer: "import ModB\n\nprotocol Local {}\nextension Base: Local {}",
            node: "class \"Base\" as Base <<ModB>>"
        ),
        Case(
            name: "a protocol both modules declare, conformed to where only ModB is imported",
            writer: "import ModB\n\nstruct S: Proto {}",
            node: "class \"Proto\" as Proto <<ModB>>"
        ),
        Case(
            name: "the file imports ModE, which re-exports ModB",
            writer: "import ModE\n\nfinal class C: Base {}", reexporter: "@_exported import ModB",
            node: "class \"Base\" as Base <<ModB>>"
        ),
        Case(
            name: "a declaration's own end: ModB's Thing, beside ModA's of that name",
            writer: "public struct CThing {}", moreOfModA: "public struct Thing {}",
            moreOfModB: "struct Thing: Proto {}", node: "class \"Thing\" as Thing <<ModB>>"
        ),
        Case(
            name: "Swift's Identifiable, beside ModA's, which the file does not import",
            writer: "struct S: Identifiable {\n    let id: Int\n}",
            moreOfModA: "public protocol Identifiable {}", node: nil, untagged: "Identifiable"
        ),
        Case(
            name: "a shared node takes the module most of its ends mean: ModA's, two to one",
            writer: "import ModB\n\nfinal class C: Base {}",
            moreOfModA: "final class AA: Base {}\nfinal class AB: Base {}", node: "class \"Base\" as Base <<ModA>>"
        ),
        Case(
            name: "a shared node takes the module most of its ends mean: ModB's, two to one",
            writer: "import ModB\n\nfinal class C: Base {}\nfinal class D: Base {}",
            moreOfModA: "final class AA: Base {}", node: "class \"Base\" as Base <<ModB>>"
        ),
    ]

    private static func declaring(_ member: String, then more: String) -> String {
        """
        open class Base {
            public init() {}
            public func \(member)() {}
        }

        public protocol Proto {}

        \(more)
        """
    }

    /// Each case is read with ModA's sources at `Sources/ModA`, read first, and at
    /// `Sources/ZModA`, read last, so no tag comes from which target is read first.
    @Test("a supertype is tagged with the module of the type the writer means", arguments: cases, [false, true])
    func tagsTheMeantModule(_ testCase: Case, modALast: Bool) throws {
        let package = try TemporaryPackage([
            (name: "ModA", files: [(name: "A.swift", source: Self.declaring("aOnly", then: testCase.moreOfModA))]),
            (name: "ModB", files: [(name: "B.swift", source: Self.declaring("bOnly", then: testCase.moreOfModB))]),
            (name: "ModC", files: [(name: "C.swift", source: testCase.writer)]),
            (name: "ModE", files: [(name: "E.swift", source: testCase.reexporter)]),
        ], paths: modALast ? ["ModA": "Sources/ZModA"] : [:])
        defer { package.remove() }
        let text = DependencyGraphGenerator().generateScript(
            forPackage: package.description(), packageRoot: package.root, mode: .types,
            with: Configuration(format: .plantuml)
        ).text
        if let node = testCase.node { #expect(text.contains(node), "\(text)") }
        if let untagged = testCase.untagged {
            #expect(!text.contains("class \"\(untagged)\""), "\(text)")
            #expect(text.contains("--> \(untagged) :"), "\(text)")
        }
    }
}
