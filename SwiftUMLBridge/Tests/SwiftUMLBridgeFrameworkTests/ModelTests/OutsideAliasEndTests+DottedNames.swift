@testable import SwiftUMLBridgeFramework
import Testing

// MARK: - A dotted name through an alias of an outside type

/// Kept in a file of its own so each stays a readable size; `First` and `Second` are declared in
/// the target `Out` that the diagram does not read, as `OutsideAliasEndTests` says.
extension OutsideAliasEndTests {
    /// `First` and `Second` are `Out`'s, which the diagram does not read, each with its own
    /// `Inner`: ModA's `Base.Inner` is `First.Inner`, and ModB's is `Second.Inner`.
    private static let dottedModA = """
        import Out
        typealias Base = First
        extension Base.Inner { func inA() {} }
        """

    private static let dottedModB = """
        import Out
        typealias Base = Second
        extension Base.Inner { func inB() {} }
        struct U: Base.Inner {}
        """

    @Test("a dotted name through an outside type's alias ends on the writer's own target's extension",
          arguments: [ExtensionVisualization.all, .merged])
    func dottedOutsideAlias(mode: ExtensionVisualization) throws {
        let items = try moduleQualifiedItems([("ModA", Self.dottedModA), ("ModB", Self.dottedModB)])
        let drawn = graph(items, mode)
        let box = try #require(drawn.owner(of: "inB"))
        #expect(box != drawn.owner(of: "inA"))
        #expect(drawn.edgeEnds.contains("U -> \(box)"))
        #expect(ClassDiagramIds.lines(of: script(items, .plantuml, mode), containing: "<|--")
            == ["Base.Inner0 <|-- U : inherits"])
    }

    @Test("Mermaid and Nomnoml end the dotted name's edge on the same box, merged or not",
          arguments: [ExtensionVisualization.all, .merged])
    func dottedOutsideAliasTextFormats(mode: ExtensionVisualization) throws {
        let items = try moduleQualifiedItems([("ModA", Self.dottedModA), ("ModB", Self.dottedModB)])
        #expect(ClassDiagramIds.lines(of: script(items, .mermaid, mode), containing: "<|--")
            == ["Base.Inner0 <|-- U : inherits"])
        #expect(ClassDiagramIds.lines(of: script(items, .nomnoml, mode), containing: "-:>")
            == ["[U] -:> inherits [Base.Inner0]"])
    }

    @Test("without modules, both read orders end the dotted name's edge on the writer's directory's extension",
          arguments: [["ModA", "ModB"], ["ModB", "ModA"]], [ExtensionVisualization.all, .merged])
    func dottedOutsideAliasDirectoryMode(order: [String], mode: ExtensionVisualization) throws {
        let sources = ["ModA": Self.dottedModA, "ModB": Self.dottedModB]
        let drawn = graph(try directoryItems(order.map { ($0, sources[$0] ?? "") }), mode)
        let box = try #require(drawn.owner(of: "inB"))
        #expect(box != drawn.owner(of: "inA"))
        #expect(drawn.edgeEnds.contains("U -> \(box)"))
    }

    /// ModB's `U`, with no `Base.Inner` extension in ModB.
    private static let dottedModBAlone = """
        import Out
        typealias Base = Second
        struct U: Base.Inner {}
        """

    /// `files` read with their modules, or as a directory-mode run reads them, without.
    private func dottedItems(_ files: [(String, String)], withModules: Bool) throws -> [SyntaxStructure] {
        withModules
            ? try moduleQualifiedItems(files.map { (module: Optional($0.0), source: $0.1) })
            : try directoryItems(files.map { (directory: $0.0, source: $0.1) })
    }

    /// As for a whole alias (`noOwnExtension`), the edge is written to the type the name comes
    /// to, `Second.Inner`, a node of its own, and never to ModA's `Base.Inner` box, with ModA
    /// read or not.
    @Test("with no extension of the member its alias comes to, the dotted name is written to that member",
          arguments: [true, false], [true, false])
    func dottedOutsideAliasNoOwnExtension(withModules: Bool, withModA: Bool) throws {
        let files = (withModA ? [("ModA", Self.dottedModA)] : []) + [("ModB", Self.dottedModBAlone)]
        let items = try dottedItems(files, withModules: withModules)
        #expect(graph(items, .all).edges.isEmpty)
        #expect(ClassDiagramIds.lines(of: script(items, .plantuml), containing: "<|--")
            == ["Second.Inner <|-- U : inherits"])
    }

    /// ModA's own `typealias Second = First` shadows `Out`'s in ModA, so its box is spelled
    /// `Second.Inner` and extends `First.Inner`. ModB's `Base.Inner` is `Out`'s `Second.Inner`:
    /// written to that name it would end on ModA's box, whose id that is, so it is left out, as
    /// in `targetSpelledLikeAnotherAlias`. Without modules, nothing says ModB does not see ModA,
    /// so ModB's `Second` is ModA's alias, the only `Second` read, and the name comes to
    /// `First.Inner`, as a whole `Base` comes to `First`: no box's id either.
    @Test("a dotted name coming to another target's extension's spelling does not end on that extension",
          arguments: [true, false])
    func dottedOutsideAliasSpelledLikeAnotherExtension(withModules: Bool) throws {
        let modA = """
            import Out
            typealias Second = First
            extension Second.Inner { func inA() {} }
            """
        let items = try dottedItems([("ModA", modA), ("ModB", Self.dottedModBAlone)], withModules: withModules)
        let drawn = graph(items, .all)
        let box = try #require(drawn.owner(of: "inA"))
        #expect(!drawn.edgeEnds.contains("U -> \(box)"))
        let lines = ClassDiagramIds.lines(of: script(items, .plantuml), containing: "<|--")
        #expect(!lines.contains { $0.hasPrefix("\(box) ") })
        if withModules { #expect(lines.isEmpty) }
    }

    /// Inside `extension Date`, `Base.Inner` may be a member of `Date`, so the name is not sure,
    /// and the edge keeps ending on the first box of its spelling, the target's only one.
    @Test("a dotted name in an extension of an outside type keeps ending on its target's extension",
          arguments: [true, false])
    func dottedOutsideAliasInOutsideExtension(withModules: Bool) throws {
        let source = """
            import Foundation
            import Out
            typealias Base = First
            extension Base.Inner { func inA() {} }
            extension Date { struct U: Base.Inner {} }
            """
        let items = try dottedItems([("App", source)], withModules: withModules)
        let drawn = graph(items, .all)
        let box = try #require(drawn.owner(of: "inA"))
        #expect(drawn.edgeEnds.contains("Date.U -> \(box)"))
        #expect(ClassDiagramIds.lines(of: script(items, .plantuml), containing: "<|--")
            == ["Base.Inner <|-- Date.U : inherits"])
    }

    /// Inside `extension Host`, `Base` is `Out`'s `Host.Base` when Host has such a member, which
    /// Swift looks in before the module-level alias, so `Base.Inner` may not be `First.Inner`.
    /// The name is left as written, as the drawn graph leaves it unsure: never spelled
    /// `First.Inner`, which would end on the project's `extension First.Inner` box, or with that
    /// box drawn, leave the edge out of the text formats, which take it for the graph's.
    @Test("a dotted name in an extension of an outside type is not spelled through the alias",
          arguments: [true, false], [true, false])
    func dottedOutsideAliasMayMeanOutsideMember(withModules: Bool, withFirstExtension: Bool) throws {
        let source = """
            import Out
            typealias Base = First
            \(withFirstExtension ? "extension First.Inner { func viaFirst() {} }" : "")
            extension Host { struct U: Base.Inner {} }
            """
        let items = try dottedItems([("App", source)], withModules: withModules)
        let drawn = graph(items, .all)
        #expect(!drawn.edgeEnds.contains { $0.hasPrefix("Host.U -> ") })
        for format in [DiagramFormat.plantuml, .mermaid] {
            #expect(ClassDiagramIds.lines(of: script(items, format), containing: "<|--")
                == ["Base.Inner <|-- Host.U : inherits"])
        }
    }

    /// A `Base` the project declares in its own `extension Host` is the one Swift means there:
    /// were Host to have a `Base` of its own, Swift would reject the name as ambiguous. So
    /// `Base.Inner` is `First.Inner`, written to that name as for an alias at file scope.
    @Test("a dotted name through an alias the project declares in an outside type's extension is followed",
          arguments: [true, false])
    func dottedOutsideAliasDeclaredInOutsideExtension(withModules: Bool) throws {
        let source = """
            import Out
            extension Host { typealias Base = First; class X: Base.Inner {} }
            """
        let items = try dottedItems([("App", source)], withModules: withModules)
        for format in [DiagramFormat.plantuml, .mermaid] {
            #expect(ClassDiagramIds.lines(of: script(items, format), containing: "<|--")
                == ["First.Inner <|-- Host.X : inherits"])
        }
    }

    /// A typealias declared inside a type is a member, recorded under `Mine.Base`, not `Base`, but
    /// `Base.Inner` written beside it is `First.Inner` all the same, so the edge ends on the
    /// project's `extension First.Inner` box, in the text formats too, which before left it out
    /// as the graph's while the graph drew nothing.
    @Test("a dotted name through a nested alias ends on the extension of the member it comes to",
          arguments: [true, false], ["struct Mine", "struct Mine {}\nextension Mine", "extension Host"])
    func dottedNestedAliasEndsOnExtension(withModules: Bool, host: String) throws {
        let source = """
            import Out
            extension First.Inner { func viaFirst() {} }
            \(host) { typealias Base = First; class X: Base.Inner {} }
            """
        let items = try dottedItems([("App", source)], withModules: withModules)
        let owner = host.hasSuffix("Host") ? "Host" : "Mine"
        let drawn = graph(items, .all)
        let box = try #require(drawn.owner(of: "viaFirst"))
        #expect(drawn.edgeEnds.contains("\(owner).X -> \(box)"))
        #expect(ClassDiagramIds.lines(of: script(items, .plantuml), containing: "<|--")
            == ["\(box) <|-- \(owner).X : inherits"])
    }

    /// A typealias a project superclass declares is a member of the subclass too, so `P.Inner`
    /// in `Outer`, a `Parent`, is `First.Inner`. Without modules the class lookup is the same.
    @Test("a dotted name through a superclass's typealias ends on the extension of the member it comes to",
          arguments: [true, false])
    func dottedInheritedAliasEndsOnExtension(withModules: Bool) throws {
        let source = """
            import Out
            extension First.Inner { func viaFirst() {} }
            class Parent { typealias P = First }
            class Outer: Parent { class X: P.Inner {} }
            """
        let drawn = graph(try dottedItems([("App", source)], withModules: withModules), .all)
        let box = try #require(drawn.owner(of: "viaFirst"))
        #expect(drawn.edgeEnds.contains("Outer.X -> \(box)"))
    }

    /// `extension Base.Inner` at file scope is `Out`'s `Base.Inner`, another type: inside `Mine`,
    /// `Base` is `Mine.Base`, so `X` ends on `extension First.Inner`, never on the first box
    /// spelled as the name is written.
    @Test("a dotted name through a nested alias does not end on a same-spelled extension of another type",
          arguments: [true, false])
    func dottedNestedAliasPassesSameSpelledExtension(withModules: Bool) throws {
        let source = """
            import Out
            extension Base.Inner { func viaOutBase() {} }
            extension First.Inner { func viaFirst() {} }
            struct Mine { typealias Base = First; class X: Base.Inner {} }
            """
        let drawn = graph(try dottedItems([("App", source)], withModules: withModules), .all)
        let box = try #require(drawn.owner(of: "viaFirst"))
        let other = try #require(drawn.owner(of: "viaOutBase"))
        #expect(drawn.edgeEnds.contains("Mine.X -> \(box)"))
        #expect(!drawn.edgeEnds.contains("Mine.X -> \(other)"))
    }

    /// `Day.FormatStyle` is `Date.FormatStyle` to Swift, as `Day` is `Date`.
    @Test("an outside type's nested name through its alias merges with the name spelled directly",
          arguments: [true, false])
    func dottedOutsideAliasMergesWithDirectSpelling(withModules: Bool) throws {
        let source = """
            import Foundation
            typealias Day = Date
            extension Day.FormatStyle { func viaDay() {} }
            extension Date.FormatStyle { func viaDate() {} }
            """
        let drawn = graph(try dottedItems([("App", source)], withModules: withModules), .merged)
        let box = try #require(drawn.owner(of: "viaDay"))
        #expect(drawn.owner(of: "viaDate") == box)
    }
}
