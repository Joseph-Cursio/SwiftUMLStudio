import Testing
@testable import SwiftUMLBridgeFramework

/// A supertype written by its short name inside the type that declares it, `class Near: Base` in
/// `enum Outer`, means `Outer.Base`: Swift looks the name up in each enclosing type first,
/// innermost first, then in the file and the module. These check that every format ends the edge
/// on that type's box, with extensions shown, merged or hidden (#157).
@Suite("A supertype named inside its enclosing type ends on the nested type")
struct NestedSupertypeScopeTests {

    static let formats: [DiagramFormat] = [.plantuml, .mermaid, .nomnoml, .svg]
    static let modes: [ExtensionVisualization] = [.all, .merged, .none]

    static let nested = """
        enum Outer {
            class Base {}
            class Near: Base {}
        }
        final class Far: Outer.Base {}
        """

    static let shadowed = """
        class Base {}
        enum Outer {
            class Base {}
            class Near: Base {}
        }
        final class Far: Base {}
        """

    private func script(
        _ source: String, _ format: DiagramFormat, _ mode: ExtensionVisualization,
        relationships: RelationshipOptions = RelationshipOptions()
    ) -> DiagramScript {
        let elements = ElementOptions(showExtensions: mode)
        let configuration = Configuration(elements: elements, relationships: relationships, format: format)
        return ClassDiagramGenerator().generateScript(for: source, with: configuration)
    }

    /// The ids the supertype edges drawn from `child` end on, in drawing order.
    private func ends(
        from child: String, _ source: String, _ format: DiagramFormat, _ mode: ExtensionVisualization,
        relationships: RelationshipOptions = RelationshipOptions()
    ) -> [String] {
        let drawn = script(source, format, mode, relationships: relationships)
        switch format {
        case .svg:
            return drawn.layoutGraph?.edges
                .filter { $0.sourceId == child && $0.style != .composition }.map(\.targetId) ?? []
        case .nomnoml:
            // `[child] -:> label [parent]`; a nesting edge starts at the parent.
            return drawn.text.split(separator: "\n").compactMap { line -> String? in
                guard line.hasPrefix("[\(child)] -"), let open = line.lastIndex(of: "[") else { return nil }
                return String(line[line.index(after: open)...].dropLast())
            }
        default:
            // `parent <|-- child : label` and `parent <|.. child : label`.
            return drawn.text.split(separator: "\n").compactMap { line -> String? in
                let words = line.split(separator: " ")
                guard words.count >= 3, ["<|--", "<|.."].contains(words[1]), words[2] == child else { return nil }
                return String(words[0])
            }
        }
    }

    /// Each format and extension mode, as `"<format> <mode>: <ends>"`, whose supertype edges
    /// from `child` do not end on exactly `expected`.
    private func misses(
        _ source: String, from child: String, expected: [String],
        relationships: RelationshipOptions = RelationshipOptions()
    ) -> [String] {
        Self.formats.flatMap { format in
            Self.modes.compactMap { mode -> String? in
                let found = ends(from: child, source, format, mode, relationships: relationships)
                return found == expected ? nil : "\(format) \(mode): \(found)"
            }
        }
    }

    @Test("beside the subclass, from an extension of the enclosing type, generic, and shadowing", arguments: [
        nested,
        "enum Outer {\n    class Base {}\n}\nextension Outer {\n    class Near: Base {}\n}",
        "enum Outer {\n    class Base<Value> {}\n    class Near: Base<Int> {}\n}",
        shadowed
    ])
    func oneLevelUp(source: String) {
        #expect(misses(source, from: "Outer.Near", expected: ["Outer.Base"]) == [])
    }

    @Test("nomnoml draws no box of its own for the short name")
    func noStrayNomnomlBox() throws {
        let graph = try NomnomlGraph(parsing: script(Self.nested, .nomnoml, .all).text)
        #expect(graph.nodes.map(\.id) == ["Outer", "Outer.Base", "Outer.Near", "Far"])
    }

    @Test("two levels down, and a partly qualified name", arguments: [
        ("A.B.Sibling", "A.B.Mid"), ("A.B.Upper", "A.Top"), ("A.C.Cousin", "A.B.Mid")
    ])
    func twoLevels(child: String, parent: String) {
        let source = """
            enum A {
                class Top {}
                enum B {
                    class Mid {}
                    class Sibling: Mid {}
                    class Upper: Top {}
                }
                enum C {
                    class Cousin: B.Mid {}
                }
            }
            """
        #expect(misses(source, from: child, expected: [parent]) == [])
    }

    @Test("a type in an extension of a nested type sees that type's members", arguments: [
        "Outer.Box.Inside", "Outer.Box.Tray.Slot"
    ])
    func extensionOfNestedType(child: String) {
        let source = """
            enum Outer {
                struct Box {
                    class Helper {}
                }
            }
            extension Outer.Box {
                class Inside: Helper {}
                struct Tray {
                    class Slot: Helper {}
                }
            }
            """
        #expect(misses(source, from: child, expected: ["Outer.Box.Helper"]) == [])
    }

    /// A nested protocol has had a box since #162, so a conformance to it by its short name can
    /// end there.
    @Test("a conformance to a protocol nested beside the type")
    func nestedProtocol() {
        let source = """
            enum Outer {
                protocol Shape {}
                struct Circle: Shape {}
            }
            struct Square: Outer.Shape {}
            """
        #expect(misses(source, from: "Outer.Circle", expected: ["Outer.Shape"]) == [])
        #expect(misses(source, from: "Square", expected: ["Outer.Shape"]) == [])
    }

    /// A typealias declared in a type reads its target as that type's members do, so `Root`
    /// means the nested `Base`, not the top-level one (#125).
    @Test("a typealias in the enclosing type names a sibling")
    func memberTypealias() {
        let source = """
            class Base {}
            enum Outer {
                class Base {}
                typealias Root = Base
                class Near: Root {}
            }
            """
        #expect(misses(source, from: "Outer.Near", expected: ["Outer.Base"]) == [])
    }

    /// A macro's conformance belongs to no type around the declaration, so a nested protocol of
    /// its name does not take it.
    @Test("a macro's conformance is not looked up in the enclosing type")
    func macroConformance() {
        let source = """
            import Observation
            enum Outer {
                protocol Observable {}
                @Observable final class Model {}
            }
            """
        #expect(ends(from: "Outer.Model", source, .plantuml, .all) == ["Observable"])
    }

    /// As for a typealias (#125), a pattern matches the name as written or the type it means.
    @Test("inheritance.exclude also matches the nested type the name means")
    func excludeAsResolved() {
        let relationships = RelationshipOptions(
            inheritance: Relationship(label: "inherits", exclude: ["Outer.Base"])
        )
        #expect(misses(Self.nested, from: "Outer.Near", expected: [], relationships: relationships) == [])
        #expect(misses(Self.nested, from: "Far", expected: [], relationships: relationships) == [])
    }

    // MARK: - Guards: what was already right

    @Test("a qualified name, and a top-level name written outside the nesting type")
    func namesOutside() {
        #expect(misses(Self.nested, from: "Far", expected: ["Outer.Base"]) == [])
        #expect(misses(Self.shadowed, from: "Far", expected: ["Base"]) == [])
    }

    @Test("a nested class inheriting from the class it is nested in")
    func enclosingClass() {
        #expect(misses("class Node {\n    final class Leaf: Node {}\n}", from: "Node.Leaf", expected: ["Node"]) == [])
    }

    /// Swift reads an extension's inheritance clause at file scope, so `Shape` here is the
    /// protocol, not the struct nested in `Outer`, also once the conformance is carried (#76).
    @Test("a merged extension's conformance is looked up from the extension", arguments: formats)
    func extensionClause(format: DiagramFormat) {
        let source = """
            protocol Shape {}
            enum Outer {
                struct Shape {}
                class Near {}
            }
            extension Outer.Near: Shape {}
            """
        #expect(ends(from: "Outer.Near", source, format, .merged) == ["Shape"])
    }

    @Test("inheritance.exclude still matches the supertype as written")
    func excludeAsWritten() {
        let relationships = RelationshipOptions(inheritance: Relationship(label: "inherits", exclude: ["Base"]))
        #expect(misses(Self.nested, from: "Outer.Near", expected: [], relationships: relationships) == [])
        #expect(misses(Self.nested, from: "Far", expected: ["Outer.Base"], relationships: relationships) == [])
    }
}
