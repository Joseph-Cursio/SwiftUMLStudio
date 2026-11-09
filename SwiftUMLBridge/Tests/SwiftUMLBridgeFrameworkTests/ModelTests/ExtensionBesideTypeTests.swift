import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

// Without a module, what a public member an extension in the type's own file adds weighs against
// another extension's in a sibling directory (#253). The file is compiled wherever the type is, so
// every file that sees `Foo` sees that member, and a file that saw a second `Foo.X` would not
// compile (`ambiguous type name 'X' in 'Foo'`): one that compiles means it, however near the other
// is, as for a public member of `Foo`'s body (`ExtensionMemberRankTests.bodyBeforeExtension`).
// Another file in `Foo`'s directory may be another target's, so it is ranked as before. Each
// fixture was built as a package with `swift build`, with the `import` lines the fixtures leave
// out, and a line that compiles only for the meant end; `--package` gives the same ends.

private typealias Fixture = NearestDirectoryFixture

private func supertypeLines(in lines: [String]) -> Set<String> {
    Set(lines.filter { $0.contains("<|") })
}

@Suite("A public member an extension in the type's file adds beats a sibling directory's, without a module")
struct ExtensionBesideTypeTests {

    /// #253's `grouped`, with Core's extension in `Foo`'s own file: targets grouped under
    /// `Features`, where `Login` adds its own `X` and `Profile`, which imports only `Core`, writes
    /// `Foo.X`. `coreMember` is the line Core's extension declares, and `coreFile` its file.
    private static func grouped(
        spelling: String, coreMember: String = "extension Foo { public typealias X = RCore }",
        coreFile: String = "/r/Sources/Core/Foo.swift"
    ) -> [Fixture.File] {
        let foo = "public struct Foo { public init() {} }\npublic typealias Crate = Foo"
        let core = "\(coreMember.replacingOccurrences(of: "extension Foo", with: "extension \(spelling)"))\n"
            + "open class RCore { public init() {} }"
        let declarations: [Fixture.File] = coreFile == "/r/Sources/Core/Foo.swift"
            ? [(coreFile, "\(foo)\n\(core)")]
            : [("/r/Sources/Core/Foo.swift", foo), (coreFile, core)]
        return declarations + [
            ("/r/Sources/Features/Login/E.swift",
             "extension \(spelling) { public typealias X = RLogin }\nopen class RLogin {}"),
            ("/r/Sources/Features/Profile/W.swift", "class W: Foo.X {}")
        ]
    }

    @Test("an extension's public alias in the type's file beats one in a sibling directory",
          arguments: ["Crate", "Foo"], [ExtensionVisualization.all, .merged, .none])
    func inTypesFileBeatsSibling(spelling: String, mode: ExtensionVisualization) throws {
        let elements = ElementOptions(showExtensions: mode)
        for files in [Self.grouped(spelling: spelling), Self.grouped(spelling: spelling).reversed()] {
            #expect(supertypeLines(in: try Fixture.lines(files, .plantuml, elements)) == ["RCore <|-- W : inherits"])
            #expect(try Fixture.edges(files, elements).contains("W -> RCore"))
        }
    }

    /// `X` inside `extension Foo` is first looked for as `Foo.X`, among the same candidates.
    @Test("a name written inside an extension takes the public alias in the type's file",
          arguments: ["Crate", "Foo"], [ExtensionVisualization.all, .merged, .none])
    func insideExtension(spelling: String, mode: ExtensionVisualization) throws {
        var files = Self.grouped(spelling: spelling)
        files[files.count - 1].source = "extension Foo { class W: X {} }"
        let elements = ElementOptions(showExtensions: mode)
        for ordered in [files, files.reversed()] {
            let lines = supertypeLines(in: try Fixture.lines(ordered, .plantuml, elements))
            #expect(lines == ["RCore <|-- Foo.W : inherits"], "\(lines)")
        }
    }

    /// `public extension` makes its members public, as `public` on each does.
    @Test("a member a public extension in the type's file declares beats one in a sibling directory",
          arguments: ["Crate", "Foo"])
    func publicExtension(spelling: String) throws {
        let files = Self.grouped(spelling: spelling, coreMember: "public extension Foo { typealias X = RCore }")
        #expect(supertypeLines(in: try Fixture.lines(files, .plantuml)) == ["RCore <|-- W : inherits"])
    }

    @Test("the resolver the other diagrams follow takes the alias in the type's file", arguments: ["Crate", "Foo"])
    func resolver(spelling: String) throws {
        let resolver = TypeAliasResolver(items: try Fixture.parsed(Self.grouped(spelling: spelling)))
        #expect(resolver.resolve("Foo.X", in: URL(fileURLWithPath: "/r/Sources/Features/Profile/Use.swift")) == "RCore")
    }

    @Test("deps --types takes the alias in the type's file", arguments: ["Crate", "Foo"])
    func typeDependencies(spelling: String) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("extension-beside-type-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for file in Self.grouped(spelling: spelling) {
            let url = root.appendingPathComponent(String(file.path.dropFirst("/r/".count)))
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try file.source.write(to: url, atomically: true, encoding: .utf8)
        }
        let text = DependencyGraphGenerator().generateScript(
            for: [root.appendingPathComponent("Sources").path], mode: .types, with: Configuration(format: .plantuml)
        ).text
        let fromWriter = text.split(separator: "\n").filter { $0.hasPrefix("W ") }
        #expect(fromWriter == ["W --> RCore : inherits"], "\(text)")
    }

    // MARK: What it leaves alone

    /// #253's own layout, Core's extension in a file of its own beside `Foo`'s, or below it. That
    /// file may be another target's: an Xcode project gives each file its own targets, and a
    /// package can split a directory with `sources:` and `exclude:`. Where it is Core's, Swift
    /// means `RCore`, and this is wrong; where it is a target `Profile` does not import, Swift
    /// means `RLogin`, and this is right. A directory cannot tell the two apart.
    @Test("an extension's public alias in another file of the type's directory is ranked by nearness, as before",
          arguments: ["/r/Sources/Core/E.swift", "/r/Sources/Core/Extensions/E.swift"])
    func otherFile(coreFile: String) throws {
        let files = Self.grouped(spelling: "Foo", coreFile: coreFile)
        #expect(supertypeLines(in: try Fixture.lines(files, .plantuml)) == ["RLogin <|-- W : inherits"])
    }

    /// An `internal` member is out of sight outside Core. A `package` one is out of sight outside
    /// Core's package, which a scan of several packages cannot see. An `@_spi` one is out of sight
    /// to a file that imports Core without that SPI. One in an `#if` is gone from a build whose
    /// condition fails, as on macOS for `os(iOS)`, where `Login` may supply the `X`. None proves
    /// which `X` `W` means.
    @Test("an alias in the type's file that not every module sees does not beat one in a sibling directory",
          arguments: [
            "extension Foo { typealias X = RCore }",
            "extension Foo { package typealias X = RCore }",
            "extension Foo { @_spi(Testing) public typealias X = RCore }",
            "@_spi(Testing) extension Foo { public typealias X = RCore }",
            "extension Foo {\n#if DEBUG\n@_spi(Testing)\n#endif\npublic typealias X = RCore\n}",
            "#if os(iOS)\nextension Foo { public typealias X = RCore }\n#endif",
            "extension Foo {\n#if os(iOS)\npublic typealias X = RCore\n#endif\n}"
          ])
    func notSeenEverywhere(coreMember: String) throws {
        let files = Self.grouped(spelling: "Foo", coreMember: coreMember)
        #expect(supertypeLines(in: try Fixture.lines(files, .plantuml)) == ["RLogin <|-- W : inherits"])
    }

    /// `public` inside `extension Foo.Inner` is no more than `Inner`, here `internal`, so `Profile`
    /// sees only the `Inner` and `X` `Login` adds.
    @Test("a public alias added to an internal nested type in the type's file is not seen everywhere")
    func memberOfInternalNestedType() throws {
        let files: [Fixture.File] = [
            ("/r/Sources/Core/Foo.swift", """
            public struct Foo { enum Inner {} }
            extension Foo.Inner { public typealias X = RCore }
            open class RCore { public init() {} }
            """),
            ("/r/Sources/Features/Login/E.swift", """
            open class RLogin { public init() {} }
            extension Foo { public enum Inner { public typealias X = RLogin } }
            """),
            ("/r/Sources/Features/Profile/W.swift", "class V: Foo.Inner.X {}\nextension Foo.Inner { class W: X {} }")
        ]
        #expect(supertypeLines(in: try Fixture.lines(files, .plantuml)) == [
            "RLogin <|-- V : inherits", "RLogin <|-- Foo.Inner.W : inherits"
        ])
    }

    /// Core and Lib each declare a `Foo`, equally near `Profile`, which imports Lib and so means
    /// Lib's `Foo` and Login's `X`. Which `Foo` is `W`'s is then a guess, and read first, Core's
    /// would make its in-file `X` look seen by every module and drop Login's. A `Foo` of the
    /// same name in a directory the package excludes is a second one too.
    @Test("an extension's public alias in the type's file does not count when another type has its name",
          arguments: ["/r/Sources/Lib/Foo.swift", "/r/Sources/Core/Legacy/Foo.swift"], [false, true])
    func anotherTypeOfTheName(otherFoo: String, reversed: Bool) throws {
        let types: [Fixture.File] = [
            ("/r/Sources/Core/Foo.swift", """
            public struct Foo { public init() {} }
            extension Foo { public typealias X = RCore }
            open class RCore { public init() {} }
            """),
            (otherFoo, "public struct Foo { public init() {} }")
        ]
        let files = (reversed ? types.reversed() : types) + [
            ("/r/Sources/Features/Login/E.swift",
             "extension Foo { public typealias X = RLogin }\nopen class RLogin {}"),
            ("/r/Sources/Features/Profile/W.swift", "class W: Foo.X {}")
        ]
        #expect(supertypeLines(in: try Fixture.lines(files, .plantuml)) == ["RLogin <|-- W : inherits"])
    }

    /// `Zed` is first read among equally near `Foo`s, so `W` and the extension beside it both read
    /// `Foo` as `Zed`'s, where Swift reads `Lib`'s. A public member an extension in `Zed`'s `Foo`'s
    /// file adds then looks like one of the type `W` means, and only the extension's being beside
    /// `W` keeps it, as for a member of the body (`ExtensionMemberRankTests.unrelatedTypeReadFirst`).
    @Test("an extension's public alias beside an unrelated type read first does not beat one beside the writer",
          arguments: [ExtensionVisualization.all, .merged, .none], [false, true])
    func unrelatedTypeReadFirst(mode: ExtensionVisualization, reversed: Bool) throws {
        let targets: [Fixture.File] = [
            ("/r/Sources/Zed/Foo.swift", """
            public struct Foo {}
            extension Foo { public typealias X = RZed }
            public class RZed {}
            """),
            ("/r/Sources/Lib/Foo.swift", "public struct Foo { public init() {} }")
        ]
        let files = (reversed ? targets.reversed() : targets) + [
            ("/r/Sources/App/App.swift", "extension Foo { typealias X = RApp }\nclass RApp {}"),
            ("/r/Sources/App/W.swift", "class W: Foo.X {}")
        ]
        #expect(supertypeLines(in: try Fixture.lines(files, .plantuml, ElementOptions(showExtensions: mode))) == [
            "RApp <|-- W : inherits"
        ])
    }
}
