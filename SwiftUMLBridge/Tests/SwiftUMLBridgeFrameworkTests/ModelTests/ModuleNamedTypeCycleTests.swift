import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

/// A name that means both a module and a type around the writer sends the lookup in a loop (#244):
/// whether the enclosing `M` is read as a module takes what `M.V`'s first component means, which
/// takes the enclosing `M` again. Each fixture builds as a package with `swift build`, and a method
/// only the expected supertype has proves which one Swift means. Before the depth went through
/// `readsModule`, each of these overflowed the stack, which ends the test run.
@Suite("A name that means both a module and a type around the writer")
struct ModuleNamedTypeCycleTests {

    private typealias Files = [(module: String?, source: String)]

    /// `class W: M.V` in the inner `M` calls the inner `V`'s method; the outer `V`'s does not build.
    private static let nestedInItsNamesake: Files = [
        ("M", """
            enum M {
                class V { func outer() {} }
                enum M {
                    class V { func inner() {} }
                    class W: M.V {}
                }
            }
            func use() { M.M.W().inner() }
            """),
    ]

    /// No type is nested in one of its own name here: `extension ModB.Base` extends the struct's
    /// `Base`, and `Thing` is that struct's.
    private static let extendedThroughNamesake: Files = [
        ("ModB", """
            public struct ModB {
                public struct Base {}
                open class Thing { public init() {} }
            }
            public enum Base {
                public struct ModB {}
            }
            """),
        ("ModB", """
            extension ModB.Base {
                class W: ModB.Thing {}
            }
            """),
    ]

    private func supertypeLines(_ files: Files, _ format: DiagramFormat) throws -> [String] {
        let script = DiagramScript(items: try moduleQualifiedItems(files), configuration: Configuration(format: format))
        return ClassDiagramIds.lines(of: script.text, containing: "<|")
    }

    private func edgeEnds(_ files: Files) throws -> [String] {
        let configuration = Configuration(format: .svg)
        return LayoutGraphBuilder.buildClassDiagram(
            from: try moduleQualifiedItems(files), configuration: configuration
        ).edgeEnds
    }

    @Test("a nested type named like its parent and its module draws the edge Swift means")
    func nestedInItsNamesakeDrawsItsEdge() throws {
        #expect(try supertypeLines(Self.nestedInItsNamesake, .plantuml) == ["M.M.V <|-- M.M.W : inherits"])
    }

    @Test("a member of a type named like its module draws the edge Swift means")
    func extendedThroughNamesakeDrawsItsEdge() throws {
        let lines = try supertypeLines(Self.extendedThroughNamesake, .plantuml)
        #expect(lines == ["ModB.Thing <|-- ModB.Base.W : inherits"])
    }

    @Test("SVG ends the edge on the declaration Swift means")
    func svgEndsOnTheMeantDeclaration() throws {
        let nested = try edgeEnds(Self.nestedInItsNamesake)
        #expect(nested.contains("M.M.W -> M.M.V"), "\(nested)")
        let extended = try edgeEnds(Self.extendedThroughNamesake)
        #expect(extended.contains("ModB.Base.W -> ModB.Thing"), "\(extended)")
    }

    @Test("the other text formats draw a diagram too", arguments: [DiagramFormat.mermaid, .nomnoml])
    func otherFormats(format: DiagramFormat) throws {
        for files in [Self.nestedInItsNamesake, Self.extendedThroughNamesake] {
            let items = try moduleQualifiedItems(files)
            let text = DiagramScript(items: items, configuration: Configuration(format: format)).text
            #expect(text.contains("W"), "\(text)")
        }
    }

    /// The guard must not cost a legal chain its last link: the walk takes that link's name at
    /// depth 8, and in `extension ModA.Foo` it means the member only through the module. Cut there,
    /// `Inner` is read as written, so the edge ends on the top-level `Inner` here, which Swift's
    /// member lookup does not mean, or with none, on a stray class.
    @Test("the last link of an eight-link alias chain is still read through its module",
          arguments: [false, true])
    func eightLinkChainKeepsItsLastLink(topLevelDecoy: Bool) throws {
        let links = (1..<8).map { "    typealias L\($0) = L\($0 + 1)" }.joined(separator: "\n")
        let modA = "public struct Foo {\n    public init() {}\n    public protocol Inner {}\n}"
        let modB = """
            import ModA

            \(topLevelDecoy ? "public protocol Inner {}" : "")

            extension ModA.Foo {
            \(links)
                typealias L8 = Inner
            }

            struct S: ModA.Foo.L1 {}
            """
        #expect(try supertypeLines([("ModA", modA), ("ModB", modB)], .plantuml) == ["Foo.Inner <|.. S : conforms to"])
    }
}
