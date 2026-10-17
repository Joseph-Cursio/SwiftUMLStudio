import Testing
@testable import SwiftUMLBridgeFramework

/// `elements.exclude: [Foo]` hides `struct Foo` and `extension Foo` together. These check the same
/// for a nested type, whether the pattern names it `Inner` or `Outer.Inner`, in every format and
/// with extensions shown, merged or hidden.
@Suite("elements.exclude hides a nested type and its extensions together")
struct NestedTypeExcludeTests {

    static let nested = """
        protocol Drawable {}
        enum Outer {
            struct Inner {
                var size = 0
            }
        }
        extension Outer.Inner: Drawable {
            func draw() {}
        }
        """

    static let formats: [DiagramFormat] = [.plantuml, .mermaid, .nomnoml, .svg]
    static let modes: [ExtensionVisualization] = [.all, .merged, .none]

    private func script(
        _ source: String,
        exclude: [String]? = nil,
        format: DiagramFormat = .plantuml,
        extensions: ExtensionVisualization = .all,
        relationships: RelationshipOptions = RelationshipOptions()
    ) -> String {
        let elements = ElementOptions(showExtensions: extensions, exclude: exclude)
        let configuration = Configuration(elements: elements, relationships: relationships, format: format)
        return ClassDiagramGenerator().generateScript(for: source, with: configuration).text
    }

    /// Each format and extension mode, as `"<format> <mode>"`, whose diagram of `source` with
    /// `exclude` still contains one of `words`.
    private func leaks(_ source: String, exclude: [String], words: [String]) -> [String] {
        Self.formats.flatMap { format in
            Self.modes.compactMap { mode -> String? in
                let text = script(source, exclude: exclude, format: format, extensions: mode)
                return words.contains { text.contains($0) } ? "\(format) \(mode)" : nil
            }
        }
    }

    @Test("each spelling hides the struct and its extension", arguments: ["Inner", "Outer.Inner", "Outer.*"])
    func bothSpellings(pattern: String) {
        #expect(leaks(Self.nested, exclude: [pattern], words: ["Inner", "draw"]) == [])
    }

    @Test("a type nested in an extension, and an extension of it", arguments: ["Row", "Panel.Row"])
    func nestedInExtension(pattern: String) {
        let source = """
            protocol Drawable {}
            struct Panel {}
            extension Panel {
                struct Row { var height = 0 }
            }
            extension Panel.Row: Drawable {
                func draw() {}
            }
            """
        #expect(leaks(source, exclude: [pattern], words: ["Row", "draw"]) == [])
    }

    static let threeLevels = """
        protocol Drawable {}
        enum A { enum B { struct C { var depth = 0 } } }
        extension A.B.C: Drawable { func draw() {} }
        """

    @Test("three levels deep, the short and the full name each hide both", arguments: ["C", "A.B.C"])
    func threeLevelsDeep(pattern: String) {
        #expect(leaks(Self.threeLevels, exclude: [pattern], words: ["depth", "draw"]) == [])
    }

    /// A pattern matches a whole name, so a partial path is neither the short nor the full one.
    @Test("a partial path hides neither")
    func partialPath() {
        let text = script(Self.threeLevels, exclude: ["B.C"], format: .mermaid)
        #expect(ClassDiagramIds.mermaid(in: text) == ["Drawable", "A", "A.B", "A.B.C", "A.B.C0"])
    }

    @Test("dependency.exclude names the extended type either way", arguments: ["Inner", "Outer.Inner"])
    func dependencyExclude(pattern: String) {
        let relationships = RelationshipOptions(dependency: Relationship(label: "ext", exclude: [pattern]))
        let text = script(Self.nested, relationships: relationships)
        #expect(ClassDiagramIds.lines(of: text, containing: " <.. ") == [])
    }

    // MARK: - Guards: these pass today, and a fix should keep them passing.

    @Test("a top-level type and its extension")
    func topLevel() {
        let source = "protocol Drawable {}\nstruct Shape { var size = 0 }\nextension Shape: Drawable { func draw() {} }"
        #expect(leaks(source, exclude: ["Shape"], words: ["Shape", "draw"]) == [])
    }

    @Test("the outer type's name does not hide what is nested in it")
    func outerOnly() {
        let text = script(Self.nested, exclude: ["Outer"], format: .mermaid)
        #expect(ClassDiagramIds.mermaid(in: text) == ["Drawable", "Outer.Inner", "Outer.Inner0"])
    }

    @Test("a qualified name does not hide another type with the same short name")
    func otherInner() {
        let source = Self.nested + "\nenum Other {\n    struct Inner {}\n}\n"
        let text = script(source, exclude: ["Outer.Inner"], format: .mermaid)
        #expect(ClassDiagramIds.mermaid(in: text).contains("Other.Inner"))
    }

    @Test("an empty list hides nothing", arguments: formats)
    func emptyList(format: DiagramFormat) {
        let empty = script(Self.nested, exclude: [], format: format, extensions: .merged)
        #expect(empty == script(Self.nested, format: format, extensions: .merged))
        #expect(empty.contains("Inner"))
    }
}
