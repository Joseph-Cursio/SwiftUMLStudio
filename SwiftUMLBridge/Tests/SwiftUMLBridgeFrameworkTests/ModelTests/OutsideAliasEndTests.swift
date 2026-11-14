import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

/// Two extensions can share a spelling and extend different types outside the diagram, as each
/// target has its own typealiases. An edge ended on the first drawn extension of that spelling,
/// whatever its own alias came to, so which box it reached depended on read order (#231). Every
/// source passes `swift build` as a SwiftPM package, with `Real` in `targetSpelledLikeAnotherAlias`,
/// and `First` and `Second` in the dotted names', declared in a target `Out` that the diagram does
/// not read.
@Suite("An edge through a typealias ends only on an extension of the type the alias comes to")
struct OutsideAliasEndTests {
    private typealias Files = [(module: String?, source: String)]

    private static let modA = """
        import Foundation
        typealias Base = NSException
        extension Base { func inA() {} }
        """

    private static let modB = """
        import Foundation
        typealias Base = NSObject
        extension Base { func inB() {} }
        class U: Base {}
        """

    func graph(_ items: [SyntaxStructure], _ mode: ExtensionVisualization) -> LayoutGraph {
        let configuration = Configuration(elements: ElementOptions(showExtensions: mode), format: .svg)
        return LayoutGraphBuilder.buildClassDiagram(from: items, configuration: configuration)
    }

    func script(
        _ items: [SyntaxStructure], _ format: DiagramFormat, _ mode: ExtensionVisualization = .all
    ) -> String {
        let configuration = Configuration(elements: ElementOptions(showExtensions: mode), format: format)
        return DiagramScript(items: items, configuration: configuration).text
    }

    /// Each file parsed as a directory-mode run parses it: no module, in a directory of its own.
    func directoryItems(_ files: [(directory: String, source: String)]) throws -> [SyntaxStructure] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var urls: [(url: URL, module: String?)] = []
        for file in files {
            let directory = root.appendingPathComponent(file.directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("\(file.directory).swift")
            try file.source.write(to: url, atomically: true, encoding: .utf8)
            urls.append((url, nil))
        }
        return SyntaxStructure.declarations(inPackageFiles: urls)
    }

    // MARK: - The writer's own extension

    @Test("the edge ends on the writer's own target's extension, however many are drawn first",
          arguments: [ExtensionVisualization.all, .merged])
    func endsOnOwnTargetsExtension(mode: ExtensionVisualization) throws {
        let items = try moduleQualifiedItems([("ModA", Self.modA), ("ModB", Self.modB)])
        let drawn = graph(items, mode)
        let box = try #require(drawn.owner(of: "inB"))
        #expect(box != drawn.owner(of: "inA"))
        #expect(drawn.edgeEnds.contains("U -> \(box)"))
        #expect(ClassDiagramIds.lines(of: script(items, .plantuml, mode), containing: "<|--")
            == ["Base0 <|-- U : inherits"])
    }

    @Test("Mermaid and Nomnoml end the edge on the same box")
    func textFormatsAgree() throws {
        let items = try moduleQualifiedItems([("ModA", Self.modA), ("ModB", Self.modB)])
        #expect(ClassDiagramIds.lines(of: script(items, .mermaid), containing: "<|--")
            == ["Base0 <|-- U : inherits"])
        #expect(ClassDiagramIds.lines(of: script(items, .nomnoml), containing: "-:>")
            == ["[U] -:> inherits [Base0]"])
    }

    @Test("read in the other order, the edge stays on the writer's own target's extension")
    func otherOrder() throws {
        let drawn = graph(try moduleQualifiedItems([("ModB", Self.modB), ("ModA", Self.modA)]), .all)
        let box = try #require(drawn.owner(of: "inB"))
        #expect(drawn.edgeEnds.contains("U -> \(box)"))
    }

    /// With the two targets' contents swapped, the writer's own extension is the first drawn.
    @Test("with the targets' contents swapped, the edge ends on the first box drawn, the writer's own")
    func swappedTargets() throws {
        let items = try moduleQualifiedItems([("ModA", Self.modB), ("ModB", Self.modA)])
        let drawn = graph(items, .all)
        let box = try #require(drawn.owner(of: "inB"))
        #expect(drawn.edgeEnds.contains("U -> \(box)"))
        #expect(ClassDiagramIds.lines(of: script(items, .plantuml), containing: "<|--")
            == ["Base <|-- U : inherits"])
    }

    @Test("without modules, both read orders end the edge on the writer's directory's extension",
          arguments: [["ModA", "ModB"], ["ModB", "ModA"]])
    func directoryModeOrders(order: [String]) throws {
        let sources = ["ModA": Self.modA, "ModB": Self.modB]
        let items = try directoryItems(order.map { ($0, sources[$0] ?? "") })
        let drawn = graph(items, .all)
        let box = try #require(drawn.owner(of: "inB"))
        #expect(drawn.edgeEnds.contains("U -> \(box)"))
    }

    // MARK: - No extension of that type

    /// With no extension of `NSObject` drawn, it is a node of its own, like any outside type.
    @Test("with no extension of the type its alias comes to, the edge is written to that type")
    func noOwnExtension() throws {
        let modBSource = """
            import Foundation
            typealias Base = NSObject
            class U: Base {}
            """
        let items = try moduleQualifiedItems([("ModA", Self.modA), ("ModB", modBSource)])
        #expect(graph(items, .all).edges.isEmpty)
        #expect(ClassDiagramIds.lines(of: script(items, .plantuml), containing: "<|--")
            == ["NSObject <|-- U : inherits"])
    }

    /// `Real` is `Out`'s class in ModB, and spells ModA's alias of `NSException` only in ModA.
    @Test("an alias's target spelled like another target's alias does not end on that alias's extension")
    func targetSpelledLikeAnotherAlias() throws {
        let modASource = """
            import Foundation
            typealias Real = NSException
            extension Real { func inA() {} }
            """
        let modBSource = """
            import Out
            typealias Base = Real
            class U: Base {}
            """
        let items = try moduleQualifiedItems([("ModA", modASource), ("ModB", modBSource)])
        #expect(graph(items, .all).edges.isEmpty)
        // Written to `Real` it would end on ModA's box, whose id that is, so it is left out.
        #expect(ClassDiagramIds.lines(of: script(items, .plantuml), containing: "<|--").isEmpty)
    }

    // MARK: - A dotted name

    /// With nested types hidden, `V` is outside the diagram, and each `Foo.V` comes to its own
    /// project type's: `Bar.V` in ModB and `Baz.V` in ModD.
    @Test("a dotted name through a typealias ends on the extension of the member it comes to",
          arguments: [ExtensionVisualization.all, .merged])
    func dottedName(mode: ExtensionVisualization) throws {
        let files: Files = [
            ("ModA", "public struct Bar { public protocol V {} }\n"),
            ("ModC", "public struct Baz { public protocol V {} }\n"),
            ("ModB", """
                import ModA
                typealias Foo = ModA.Bar
                extension Foo.V { func inB() {} }
                """),
            ("ModD", """
                import ModC
                typealias Foo = ModC.Baz
                extension Foo.V { func inD() {} }
                struct U: Foo.V {}
                """),
        ]
        let elements = ElementOptions(showNestedTypes: false, showExtensions: mode)
        let drawn = LayoutGraphBuilder.buildClassDiagram(
            from: try moduleQualifiedItems(files), configuration: Configuration(elements: elements, format: .svg)
        )
        let box = try #require(drawn.owner(of: "inD"))
        #expect(box != drawn.owner(of: "inB"))
        #expect(drawn.edgeEnds.contains("U -> \(box)"))
    }

    // MARK: - A name that is not sure

    /// In ModB, inside `extension Date`, `Sendable` is Swift's protocol, or a member of `Date`
    /// the lookup cannot see: never ModA's alias of `NSException`, which ModB does not import.
    @Test("a name that is not sure does not end on an extension of a sure type of that spelling")
    func unsureNameSkipsSureExtension() throws {
        let modASource = """
            import Foundation
            typealias Sendable = NSException
            extension Sendable { func inA() {} }
            """
        let modBSource = """
            import Foundation
            extension Date { struct Held: Sendable {} }
            """
        let drawn = graph(try moduleQualifiedItems([("ModA", modASource), ("ModB", modBSource)]), .all)
        let box = try #require(drawn.owner(of: "inA"))
        #expect(!drawn.edgeEnds.contains("Date.Held -> \(box)"))
    }

    /// `Date.Thing` is unsure both for the extension and for the edge, and is one type to Swift.
    @Test("a name that is not sure ends on an extension of that spelling just as unsure")
    func unsureNameEndsOnUnsureExtension() throws {
        let source = """
            import Foundation
            extension Date { typealias Thing = CustomStringConvertible }
            extension Date.Thing { func viaThing() {} }
            struct S: Date.Thing { var description: String { "" } }
            """
        let drawn = graph(try moduleQualifiedItems([("App", source)]), .all)
        let box = try #require(drawn.owner(of: "viaThing"))
        #expect(drawn.edgeEnds.contains("S -> \(box)"))
    }

    // MARK: - One alias, one target

    /// The same alias, drawn once: nothing here needs telling apart (#125).
    @Test("one target's alias still ends on its own extension, in a later file too")
    func oneTargetsAlias() throws {
        let alias = """
            typealias Describable = CustomStringConvertible
            extension Describable { var shout: String { description } }
            """
        let later = """
            struct S: Describable { var description: String { "" } }
            """
        let drawn = graph(try moduleQualifiedItems([("App", alias), ("App", later)]), .all)
        let box = try #require(drawn.owner(of: "shout"))
        #expect(drawn.edgeEnds.contains("S -> \(box)"))
    }
}
