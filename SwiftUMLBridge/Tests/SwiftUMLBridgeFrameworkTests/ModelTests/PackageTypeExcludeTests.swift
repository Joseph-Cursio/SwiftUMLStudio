import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

/// `deps --types --package --exclude` matches an end by its name as it comes and spelled with
/// its module, which is how a split node is drawn (#202), so one module's `Base` can be hidden
/// while the other's stays, and a type is hidden however it is written. Every case builds with
/// swiftc.
@Suite("deps --types --package --exclude matches a type as it comes and spelled with its module")
struct PackageTypeExcludeTests {
    struct ExcludeCase: Sendable, CustomTestStringConvertible {
        let name: String
        let pattern: String
        let writer: String
        var moreOfModA = ""
        /// PlantUML lines that must appear.
        var lines: [String] = []
        /// Text that must not appear.
        let absent: [String]

        var testDescription: String { name }
    }

    static let excludeCases: [ExcludeCase] = [
        ExcludeCase(
            name: "--exclude ModA.Base hides ModA's split Base and keeps ModB's", pattern: "ModA.Base",
            writer: "import ModB\n\nfinal class C: Base {}", moreOfModA: "final class AA: Base {}",
            lines: ["C --> ModB.Base : inherits"], absent: ["AA -->"]
        ),
        ExcludeCase(
            name: "--exclude ModB.Base hides ModB's Base, written with its module or without",
            pattern: "ModB.Base",
            writer: "import ModB\n\nfinal class C: ModB.Base {}\nfinal class D: Base {}", absent: ["-->"]
        ),
        ExcludeCase(
            name: "--exclude Base hides an extension of Base written with a module or through an alias",
            pattern: "Base",
            writer: "import ModA\nimport ModB\n\nprotocol P {}\nprotocol Q {}\nextension ModB.Base: P {}\n"
                + "extension AliasA: Q {}\nfinal class BB: ModB.Base {}",
            moreOfModA: "final class AA: Base {}\n\npublic typealias AliasA = Base", absent: ["-->"]
        ),
    ]

    /// An `enum ModA` nesting a `Base` protocol, which `ModA.Base` means wherever the enum is
    /// visible, Swift reading a type before a module, and a struct conforming to it.

    private static func source(_ member: String, then more: String) -> String {
        PackageTypeImportTests.declaring(member, then: more)
    }

    @Test("--exclude matches a type as it comes and spelled with its module", arguments: excludeCases)
    func excludeMatchesEveryName(_ testCase: ExcludeCase) throws {
        let package = try TemporaryPackage([
            (name: "ModA", files: [(name: "A.swift", source: Self.source("aOnly", then: testCase.moreOfModA))]),
            (name: "ModB", files: [(name: "B.swift", source: Self.source("bOnly", then: ""))]),
            (name: "ModC", files: [(name: "C.swift", source: testCase.writer)]),
        ])
        defer { package.remove() }
        let text = DependencyGraphGenerator().generateScript(
            forPackage: package.description(), packageRoot: package.root, mode: .types,
            with: Configuration(elements: ElementOptions(exclude: [testCase.pattern]), format: .plantuml)
        ).text
        for line in testCase.lines { #expect(text.contains(line), "\(text)") }
        for absent in testCase.absent { #expect(!text.contains(absent), "\(text)") }
    }
}
