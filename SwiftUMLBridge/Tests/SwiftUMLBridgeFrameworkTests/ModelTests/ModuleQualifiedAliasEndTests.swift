import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// An extension spelled through a typealias with its module first, `extension
/// MyModule.Describable` after `typealias Describable = CustomStringConvertible`, extends the type
/// the alias comes to, as `extension Describable` does, and `--merge-extensions` gives it one box
/// with `extension CustomStringConvertible` (#124). The edge ends looked an outside type's
/// alias-spelled extensions up only under a name a typealias is recorded under, which
/// `MyModule.Describable` is not: `struct T: CustomStringConvertible` and `struct S: Describable`
/// reached no box, and under `--merge-extensions` both edges were dropped in SVG. Every source
/// passes `swiftc -typecheck` as a SwiftPM package.
@Suite("An extension spelled through a module-qualified typealias ends every spelling's edges")
struct ModuleQualifiedAliasEndTests {

    private func graph(
        _ files: [(module: String?, source: String)], _ mode: ExtensionVisualization
    ) throws -> LayoutGraph {
        let configuration = Configuration(elements: ElementOptions(showExtensions: mode), format: .svg)
        return LayoutGraphBuilder.buildClassDiagram(from: try moduleQualifiedItems(files), configuration: configuration)
    }

    private func lines(
        _ files: [(module: String?, source: String)], _ mode: ExtensionVisualization, containing marker: String
    ) throws -> [String] {
        let configuration = Configuration(elements: ElementOptions(showExtensions: mode), format: .plantuml)
        let script = DiagramScript(items: try moduleQualifiedItems(files), configuration: configuration)
        return ClassDiagramIds.lines(of: script.text, containing: marker)
    }

    private static let ownModule = """
        typealias Describable = CustomStringConvertible
        extension MyModule.Describable { var shout: String { description.uppercased() } }
        struct S: Describable { var description: String { "s" } }
        struct T: CustomStringConvertible { var description: String { "t" } }
        """

    @Test("both spellings end on the one extension a module qualifies the alias of",
          arguments: [ExtensionVisualization.all, .merged])
    func ownModuleQualifiedAlias(mode: ExtensionVisualization) throws {
        let files: [(module: String?, source: String)] = [("MyModule", Self.ownModule)]
        let drawn = try graph(files, mode)
        let box = try #require(drawn.owner(of: "shout"))
        #expect(drawn.edgeEnds.contains("S -> \(box)"))
        #expect(drawn.edgeEnds.contains("T -> \(box)"))
        #expect(try lines(files, mode, containing: "<|--")
            == ["MyModule.Describable <|-- S : inherits", "MyModule.Describable <|-- T : inherits"])
    }

    /// Merged, `extension CustomStringConvertible` folds into the first extension, spelled
    /// `MyModule.Describable`, and both edges end on that box.
    @Test("merged with the type's own spelling, both edges end on the box it merged into")
    func mergedWithOwnSpelling() throws {
        let source = Self.ownModule + "\nextension CustomStringConvertible { var direct: Int { 0 } }\n"
        let files: [(module: String?, source: String)] = [("MyModule", source)]
        let drawn = try graph(files, .merged)
        let box = try #require(drawn.owner(of: "shout"))
        #expect(drawn.owner(of: "direct") == box)
        #expect(drawn.edgeEnds.contains("S -> \(box)"))
        #expect(drawn.edgeEnds.contains("T -> \(box)"))
    }

    /// Lib declares the alias; App extends it through Lib, and a conformance written through Lib
    /// reaches App's `extension Describable` too.
    @Test("another module's alias, spelled through that module, is an end for every spelling")
    func otherModulesAlias() throws {
        let lib = "public typealias Describable = CustomStringConvertible\n"
        let qualified = """
            import Lib
            extension Lib.Describable { var shout: String { description.uppercased() } }
            struct T: CustomStringConvertible { var description: String { "t" } }
            """
        let qualifiedGraph = try graph([("Lib", lib), ("App", qualified)], .all)
        let box = try #require(qualifiedGraph.owner(of: "shout"))
        #expect(qualifiedGraph.edgeEnds.contains("T -> \(box)"))

        let plain = """
            import Lib
            extension Describable { var shout: String { description.uppercased() } }
            struct R: Lib.Describable { var description: String { "r" } }
            """
        let plainGraph = try graph([("Lib", lib), ("App", plain)], .all)
        let plainBox = try #require(plainGraph.owner(of: "shout"))
        #expect(plainGraph.edgeEnds.contains("R -> \(plainBox)"))
    }
}
