import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

// Without a module, a member of `Foo` every module sees goes before an extension's `Foo.X` in
// another directory (`ExtensionMemberRankTests.bodyBeforeExtension`, #253). One of `Foo`'s body
// marked `@_spi(T)` is seen from another module only by a file that imports with `@_spi(T)`, so
// for a file that imports nothing with `@_spi` it proves nothing, and the `X` nearest by
// directory stays. A file that does may have opened `Foo`'s module's SPI, which a scan without a
// package cannot tell, and it still comes first there. Each fixture was built as a package with
// `swift build`, with the `import` lines given, `Profile` depending on `Core` and `Login`, and a
// line that compiles only for the meant end.

private typealias Fixture = NearestDirectoryFixture

private func supertypeLines(in lines: [String]) -> Set<String> {
    Set(lines.filter { $0.contains("<|") })
}

@Suite("A body member marked @_spi counts as seen with its type only where the writer imports with @_spi")
struct SPIMemberTests {

    /// Core's `Foo`, with `member` in its body or `extension` in its file; `Login`'s public `X`
    /// in a sibling directory; and `writer` in `Profile`.
    private static func files(body member: String = "", extension: String = "", writer: String) -> [Fixture.File] {
        [
            ("/r/Sources/Core/Foo.swift", """
            public struct Foo { \(member) public init() {} }
            \(`extension`)
            open class RCore { public init() {} }
            """),
            ("/r/Sources/Features/Login/E.swift",
             "extension Foo { public typealias X = RLogin }\nopen class RLogin { public init() {} }"),
            ("/r/Sources/Features/Profile/W.swift", writer)
        ]
    }

    private static let bodyMember = "@_spi(T) public typealias X = RCore;"
    private static let extensionMember = "extension Foo { @_spi(T) public typealias X = RCore }"

    @Test("an @_spi member does not beat a sibling directory's for a file with plain imports",
          arguments: [true, false])
    func plainImport(inBody: Bool) throws {
        let writer = "import Core\nimport Login\nclass W: Foo.X {}"
        let files = inBody
            ? Self.files(body: Self.bodyMember, writer: writer)
            : Self.files(extension: Self.extensionMember, writer: writer)
        for mode in [ExtensionVisualization.all, .merged, .none] {
            let lines = try Fixture.lines(files, .plantuml, ElementOptions(showExtensions: mode))
            #expect(supertypeLines(in: lines) == ["RLogin <|-- W : inherits"], "\(mode)")
        }
    }

    @Test("an @_spi body member beats a sibling directory's for a file that imports with @_spi")
    func spiImport() throws {
        let writers = [
            "@_spi(T) import Core\nclass W: Foo.X {}", "@_spi(T) import Core\nextension Foo { class W: X {} }"
        ]
        for writer in writers {
            let files = Self.files(body: Self.bodyMember, writer: writer)
            let lines = supertypeLines(in: try Fixture.lines(files, .plantuml))
            #expect(lines.count == 1 && lines.allSatisfy { $0.hasPrefix("RCore <|-- ") }, "\(lines)")
        }
    }

    /// `@_spi(T) import Helper` opens Helper's group `T`, not Core's. A file cannot say which
    /// module's group an `@_spi` import opens, so an extension's member so marked never counts.
    @Test("an @_spi member an extension in the type's file adds does not beat a sibling directory's")
    func extensionMemberWithSPIImport() throws {
        let writer = "import Core\nimport Login\n@_spi(T) import Helper\nclass W: Foo.X {}"
        let files = Self.files(extension: Self.extensionMember, writer: writer)
            + [("/r/Sources/Helper/H.swift", "@_spi(T) public struct HelperThing {}")]
        #expect(supertypeLines(in: try Fixture.lines(files, .plantuml)) == ["RLogin <|-- W : inherits"])
    }

    /// Two writers in one directory, one importing with `@_spi` and one not, each get their own
    /// answer, though what one name means is shared among the writers of a directory where it can be.
    /// They are two targets that share `Profile` through `sources:`: in one target, `W2`'s
    /// `import Login` would show `Login`'s `X` to `W1` too, and `W1` would not compile.
    @Test("writers in one directory that differ in importing with @_spi each get their own answer")
    func writersApart() throws {
        var files = Self.files(body: Self.bodyMember, writer: "@_spi(T) import Core\nclass W1: Foo.X {}")
        files.append(("/r/Sources/Features/Profile/W2.swift", "import Core\nimport Login\nclass W2: Foo.X {}"))
        for ordered in [files, files.reversed()] {
            #expect(supertypeLines(in: try Fixture.lines(ordered, .plantuml)) == [
                "RCore <|-- W1 : inherits", "RLogin <|-- W2 : inherits"
            ])
        }
    }

    @Test("a file that imports with @_spi records so among its imports, and only such a file")
    func parsed() throws {
        let spi = try #require(SyntaxStructure.create(from: "@_spi(T) import Core\nstruct S {}")?.substructure?.first)
        #expect(spi.imports == ["Core", ImportExtractor.spiImport])
        let plain = try #require(SyntaxStructure.create(from: "import Core\nstruct S {}")?.substructure?.first)
        #expect(plain.imports == ["Core"])
    }

    /// The entry is no module, though a target could be named as its C99 form is.
    @Test("a module's loads leave out the entry for an import with @_spi")
    func moduleLoads() {
        let lookalike = ModuleQualifiers.c99Name(of: ImportExtractor.spiImport)
        let loads = ModuleLoads(importsForModule: ["App": ["Core", ImportExtractor.spiImport], lookalike: []])
        #expect(!loads.loaded(by: "App").contains(lookalike))
        #expect(loads.loaded(by: "App").contains("Core"))
    }
}
