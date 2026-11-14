import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

private typealias File = NearestDirectoryFixture.File

private func parsed(_ files: [File]) throws -> [SyntaxStructure] {
    try NearestDirectoryFixture.parsed(files)
}

private func edges(_ files: [File], _ elements: ElementOptions = ElementOptions()) throws -> [String] {
    try NearestDirectoryFixture.edges(files, elements)
}

private func lines(
    _ files: [File], _ format: DiagramFormat, _ elements: ElementOptions = ElementOptions()
) throws -> [String] {
    try NearestDirectoryFixture.lines(files, format, elements)
}

@Suite("Ranking by directory reaches extensions, typealiases and hidden types")
struct NearestDirectoryNameTests {

    // MARK: - Extensions

    private static let parser: [File] = [
        ("/co/Yams/Sources/Yams/Parser.swift", "class Parser { func yams() {} }"),
        ("/co/swift-syntax/Sources/SwiftParser/Parser.swift", "struct Parser { func syntax() {} }"),
        ("/co/swift-syntax/Sources/SwiftParser/Statements.swift",
         "extension Parser {\n  func added() {}\n  enum StatementLabel {}\n}"),
    ]

    private func parser(yamsFirst: Bool) -> [File] {
        yamsFirst ? Self.parser : [Self.parser[1], Self.parser[0], Self.parser[2]]
    }

    /// #78's own case, from swift-syntax and Yams.
    @Test("an extension and its nested type end on the type in the extension's tree", arguments: [false, true])
    func extensionStaysHome(yamsFirst: Bool) throws {
        let own = yamsFirst ? "Parser_1" : "Parser"
        #expect(Set(try edges(parser(yamsFirst: yamsFirst))) == [
            "\(own) -> Parser.StatementLabel", "Parser_2 -> \(own)"
        ])
        #expect(try lines(parser(yamsFirst: yamsFirst), .plantuml)
            .contains { $0.hasPrefix("\(yamsFirst ? "Parser0" : "Parser") <.. ") })
    }

    /// `mergeExtensions` asks the same lookup: its members and its nested type are on one box.
    @Test("a merged extension's members and nested type go to the type in its tree, in every format",
          arguments: [false, true])
    func mergedExtensionStaysHome(yamsFirst: Bool) throws {
        let files = parser(yamsFirst: yamsFirst)
        let merged = ElementOptions(showExtensions: .merged)
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: try parsed(files), configuration: Configuration(elements: merged, format: .svg)
        )
        let box = try #require(graph.nodes.first { node in
            node.compartments.flatMap(\.items).contains { $0.contains("syntax") }
        })
        #expect(box.compartments.flatMap(\.items).contains { $0.contains("added") })
        #expect(graph.edges.map { "\($0.sourceId) -> \($0.targetId)" } == ["\(box.id) -> Parser.StatementLabel"])
        let alias = yamsFirst ? "Parser0" : "Parser"
        #expect(try lines(files, .plantuml, merged).contains("\(alias) +-- Parser.StatementLabel"))
        #expect(try lines(files, .nomnoml, merged).contains("[\(alias)] +- [Parser.StatementLabel]"))
    }

    /// A hidden type's extension stands in for it, and a nearer hidden type is the one meant:
    /// the box is the extension's, not the far drawn type's, with the member and the nested type.
    @Test("an extension of a nearer hidden type stands in for it rather than merging into a farther drawn one")
    func hiddenNearerTypeStandsIn() throws {
        var elements = ElementOptions(showExtensions: .merged)
        elements.havingAccessLevel = [.public]
        let files: [File] = [
            ("/r/A/Foo.swift", "public struct Foo { public func far() {} }"),
            ("/r/B/Foo.swift", "struct Foo {}"),
            ("/r/B/Ext.swift", "extension Foo {\n  public struct Inner {}\n  public func added() {}\n}"),
        ]
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: try parsed(files), configuration: Configuration(elements: elements, format: .svg)
        )
        let far = try #require(graph.nodes.first { node in
            node.compartments.flatMap(\.items).contains { $0.contains("far") }
        })
        #expect(!far.compartments.flatMap(\.items).contains { $0.contains("added") })
        let box = try #require(graph.nodes.first { node in
            node.compartments.flatMap(\.items).contains { $0.contains("added") }
        })
        #expect(graph.edges.contains { $0.sourceId == box.id && $0.targetId == "Foo.Inner" })
    }

    // MARK: - Typealiases

    private static let aliases: [File] = [
        ("/r/A/Alias.swift", "typealias Foo = RealA"),
        ("/r/B/Alias.swift", "typealias Foo = RealB"),
    ]

    @Test("the names sequence, activity and deps --types write follow the nearer typealias")
    func resolverGoesByDirectory() throws {
        let resolver = TypeAliasResolver(items: try parsed(Self.aliases))
        #expect(resolver.resolve("Foo", in: URL(fileURLWithPath: "/r/A/Use.swift")) == "RealA")
        #expect(resolver.resolve("Foo", in: URL(fileURLWithPath: "/r/B/Use.swift")) == "RealB")
        #expect(resolver.resolve("Foo", from: DeclarationScope(filePath: "/r/B/Use.swift", module: nil)) == "RealB")
    }

    /// Known gap: `--entry` is typed in, so it has no file to rank from, while a caller in `/r/B`
    /// has: a traversal from `Foo.run` starts at the first that declares `run`
    /// (`EntryThroughLaterDeclarationTests`), whatever `/r/B`'s callers mean.
    @Test("a name with no file to rank from means the first typealias")
    func entryPointHasNoDirectory() throws {
        #expect(TypeAliasResolver(items: try parsed(Self.aliases)).resolve("Foo", in: nil) == "RealA")
    }

    @Test("a nearer typealias beats a farther type, and among equals the type comes first")
    func nearerTypealias() throws {
        #expect(try edges([
            ("/r/A/Foo.swift", "class Foo {}"),
            ("/r/B/Alias.swift", "typealias Foo = RealB"),
            ("/r/B/RealB.swift", "class RealB {}"),
            ("/r/B/Sub.swift", "class Sub: Foo {}"),
        ]) == ["Sub -> RealB"])
        #expect(try edges([
            ("/r/A/Alias.swift", "typealias Foo = Real"),
            ("/r/A/Real.swift", "class Real {}"),
            ("/r/B/Foo.swift", "class Foo {}"),
            ("/r/C/Sub.swift", "class Sub: Foo {}"),
        ]) == ["Sub -> Foo"])
    }

    /// A's `Day` is the alias to `Date`, so `Style` in A's `extension Day` may be `Date.FormatStyle`,
    /// and `extension Day.Style` is no fallback for the protocol `FormatStyle`, however B's
    /// `struct Day` is recorded first. The one input telling the tier apart in `nearestVisible`.
    @Test("an extension of a nearer alias to an outside type is read as outside, beside a farther same-named type",
          arguments: [ExtensionVisualization.all, .merged])
    func nearerAliasToOutsideType(mode: ExtensionVisualization) throws {
        let files: [File] = [
            ("/r/A/Day.swift", "import Foundation\ntypealias Day = Date"),
            ("/r/B/Day.swift", "struct Day {}"),
            ("/r/A/Ext.swift", """
                import Foundation
                extension Day { typealias Style = FormatStyle }
                extension Day.Style { var probeZone: TimeZone { timeZone } }
                """),
            ("/r/A/Shouty.swift", """
                import Foundation
                struct Shouty: FormatStyle { func format(_ value: String) -> String { value.uppercased() } }
                """),
        ]
        let elements = ElementOptions(showExtensions: mode)
        #expect(try !edges(files, elements).contains { $0.hasPrefix("Shouty ") })
        #expect(try lines(files, .plantuml, elements).contains("FormatStyle <|-- Shouty : inherits"))
    }

    /// Known wrong: a nearer alias can close a cycle that the first of each name would not, in
    /// sources that are no one module, since Swift rejects the cycle. The depth guard ends it, and
    /// the edge is lost.
    @Test("known wrong: a nearer alias that closes a cycle loses the edge")
    func aliasCycle() throws {
        #expect(try edges([
            ("/r/P/B/u.swift", "struct U {}"),
            ("/r/P/C/t.swift", "struct T {}"),
            ("/r/P/A/a.swift", "typealias T = U"),
            ("/r/P/A/sub/u.swift", "typealias U = T"),
            ("/r/P/A/w.swift", "class W: T {}"),
        ]).isEmpty)
    }

    // MARK: - Hidden nested types

    private static let hiddenNested = ElementOptions(showNestedTypes: false)

    /// A hidden `V` ranks as it would were it recorded. It used to outrank any alias outside the
    /// writer's file, being first, so `W` in `/r/Near` lost its edge.
    @Test("a nearer typealias is not shadowed by a farther hidden nested type")
    func nearerAliasBeatsFartherHiddenType() throws {
        let files: [File] = [
            ("/r/Far/Foo.swift", "struct Foo { class V {} }"),
            ("/r/Near/Foo.swift", "struct Foo { typealias V = Base }"),
            ("/r/Near/Base.swift", "class Base {}"),
            ("/r/Near/W.swift", "class W: Foo.V {}"),
        ]
        #expect(try edges(files, Self.hiddenNested) == ["W -> Base"])
        #expect(try lines(files, .plantuml, Self.hiddenNested).contains("Base <|-- W : inherits"))
    }

    @Test("a nearer hidden nested type still takes the name from a farther typealias")
    func nearerHiddenTypeShadowsFartherAlias() throws {
        #expect(try edges([
            ("/r/Far/Foo.swift", "struct Foo { typealias V = Base }"),
            ("/r/Far/Base.swift", "class Base {}"),
            ("/r/Near/Foo.swift", "struct Foo { class V {} }"),
            ("/r/Near/W.swift", "class W: Foo.V {}"),
        ], Self.hiddenNested).isEmpty)
    }

    /// `Box.Inner.Stamp` is a typealias of `Date` in `/r/Far` and a struct in `/r/Near`, both
    /// hidden. Whether `extension Box.Inner.Stamp` is of a project type took the first hidden
    /// entry in read order, so with `/r/Far` read first it was judged an extension of `Date`,
    /// `Style` may have been a member of `Date`, and `T` lost its edge (#232). The drawn
    /// `extension CustomStringConvertible` is what makes the text formats leave an unsure edge out.
    private static func hiddenStamp(writerIn writer: String) -> [File] {
        [
            ("/r/Far/Box.swift", "import Foundation\nstruct Box { struct Inner { typealias Stamp = Date } }"),
            ("/r/Near/Box.swift", "struct Box { struct Inner { struct Stamp {} } }"),
            ("/r/\(writer)/Ext.swift", "extension Box.Inner.Stamp { typealias Style = CustomStringConvertible }"),
            ("/r/\(writer)/T.swift", "struct T: Box.Inner.Stamp.Style { var description: String { \"\" } }"),
            ("/r/\(writer)/Thing.swift", "extension CustomStringConvertible { func thi() {} }"),
        ]
    }

    @Test("an extension of a nearer hidden nested type is the project's, whichever directory is read first",
          arguments: [ExtensionVisualization.all, .merged], [false, true])
    func nearerHiddenTypeDecidesTheExtension(mode: ExtensionVisualization, farFirst: Bool) throws {
        let near = Self.hiddenStamp(writerIn: "Near")
        let files = farFirst ? near : near.reversed()
        let elements = ElementOptions(showNestedTypes: false, showExtensions: mode)
        #expect(try edges(files, elements).contains { $0.hasPrefix("T -> ") })
        for format in [DiagramFormat.plantuml, .mermaid] {
            #expect(try lines(files, format, elements).contains("CustomStringConvertible <|-- T : inherits"))
        }
        #expect(try lines(files, .nomnoml, elements).contains("[T] -:> inherits [CustomStringConvertible]"))
    }

    /// Written in `/r/Far`, `Box.Inner.Stamp` is Far's alias of `Date`, so `Style` may be a member
    /// of `Date` and the edge is left out. `T` does conform; the order of the paths no longer
    /// decides it, but the caution about an outside type's members still drops the edge.
    @Test("known wrong: a writer beside the hidden alias of an outside type loses the edge in either order",
          arguments: [false, true])
    func writerBesideHiddenOutsideAlias(farFirst: Bool) throws {
        let far = Self.hiddenStamp(writerIn: "Far")
        let files = farFirst ? far : far.reversed()
        let elements = ElementOptions(showNestedTypes: false, showExtensions: .all)
        #expect(try !edges(files, elements).contains { $0.hasPrefix("T -> ") })
        #expect(try !lines(files, .plantuml, elements).contains { $0.hasSuffix("<|-- T : inherits") })
    }

    // MARK: - Still a guess

    /// A directory is a guess at a module, so a nearer type's kind is no surer than the first's.
    @Test("the nearer type's box names the edge, and a nearer hidden protocol's kind stays unsure")
    func kindStaysAGuess() throws {
        let protocolNear: [File] = [
            ("/r/Far/Service.swift", "class Service {}"),
            ("/r/Near/Service.swift", "protocol Service {}"),
            ("/r/Near/Impl.swift", "class Impl: Service {}"),
        ]
        #expect(try lines(protocolNear, .plantuml).contains("Service <|.. Impl : conforms to"))
        #expect(try lines(protocolNear, .plantuml, ElementOptions(exclude: ["Service"]))
            .contains("Service <|-- Impl : inherits"))
        let protocolFar: [File] = [
            ("/r/Far/Service.swift", "protocol Service {}"),
            ("/r/Near/Service.swift", "class Service {}"),
            ("/r/Near/Impl.swift", "class Impl: Service {}"),
        ]
        #expect(try lines(protocolFar, .plantuml).contains("Service0 <|-- Impl : inherits"))
    }
}
