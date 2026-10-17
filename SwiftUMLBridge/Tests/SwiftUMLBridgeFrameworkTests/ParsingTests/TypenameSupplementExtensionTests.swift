import Testing
@testable import SwiftUMLBridgeFramework

/// In `var a, b: T` only `b` has a type annotation in the syntax; `a` gets `T` from the SourceKit
/// typename supplement. These check that it does so in an extension and in a type nested in one,
/// for a name in backticks, and that no variable gets the type of a different variable with the
/// same dotted name.
@Suite("The typename supplement gives each variable its own type")
struct TypenameSupplementExtensionTests {

    /// The member lines of the PlantUML class whose alias is `alias`, trimmed.
    private func members(of alias: String, in source: String) -> [String] {
        let text = ClassDiagramGenerator().generateScript(for: source, with: Configuration(format: .plantuml)).text
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.hasPrefix("class ") && $0.contains(" as \(alias) <<") }) else {
            return ["no class \(alias) in:\n\(text)"]
        }
        return lines[(start + 1)...].prefix { !$0.hasPrefix("}") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// A file that declares `prelude`, then `extension <extended> { <nested> }`.
    private static func file(
        _ prelude: String, _ extended: String, _ nested: String = "struct Deep { var a, b: Int }"
    ) -> String {
        "\(prelude)\nextension \(extended) {\n    \(nested)\n}\n"
    }

    @Test("a struct nested in an extension, as one nested in the type itself")
    func nestedInExtension() {
        let source = """
            struct Point {
                struct Offset { var dx, dy: Double }
            }
            extension Point {
                struct Delta { var dx, dy: Double }
            }
            """
        #expect(members(of: "Point.Offset", in: source) == ["~dx : Double", "~dy : Double"])
        #expect(members(of: "Point.Delta", in: source) == ["~dx : Double", "~dy : Double"])
    }

    @Test("every way an extension names its type", arguments: [
        (file("enum Outer { struct Inner {} }", "Outer.Inner"), "Outer.Inner.Deep"),
        (file("struct Box<T> {}", "Box<Int>"), "Box.Deep"),
        (file("struct Box<T> {}", "Box where T == Int"), "Box.Deep"),
        (file("", "Array where Element == Int"), "Array.Deep"),
        (file("", "[String]"), "Array.Deep"),
        (file("", "Int?"), "Optional.Deep"),
        (file("", "Swift.String"), "Swift.String.Deep"),
        (file("struct `Plain` {}", "`Plain`"), "Plain.Deep"),
        (file("actor Job {}", "Job", "final class Deep { var a, b: Int; init() { a = 0; b = 0 } }"), "Job.Deep"),
        (file("struct Map {}", "Map", "enum Layer { struct Deep { var a, b: Int } }"), "Map.Layer.Deep")
    ])
    func extendedTypeForms(source: String, alias: String) {
        #expect(members(of: alias, in: source) == ["~a : Int", "~b : Int"])
    }

    @Test("a static optional declared in the extension itself")
    func staticOptionalInExtension() {
        let source = """
            struct Settings {}
            extension Settings {
                @MainActor static var width, height: Double?
            }
            """
        #expect(members(of: "Settings0", in: source) == ["~{static} width : Double?", "~{static} height : Double?"])
    }

    @Test("a keyword name in backticks")
    func keywordName() {
        let source = """
            struct Option {
                var `default`, fallback: String
            }
            """
        #expect(members(of: "Option", in: source) == ["~`default` : String", "~fallback : String"])
    }

    @Test("a type nested in an extension does not give its types to a top-level type of its name")
    func sameNameAtTopLevel() {
        let source = """
            struct Size {
                var width, height: Int
            }
            struct Canvas {}
            extension Canvas {
                struct Size { var width, height: Double }
            }
            """
        #expect(members(of: "Size", in: source) == ["~width : Int", "~height : Int"])
        #expect(members(of: "Canvas.Size", in: source) == ["~width : Double", "~height : Double"])
    }

    @Test("a variable with an initializer takes no type from another one with its dotted name")
    func sameNameWithInitializer() {
        let source = """
            struct Inner {
                var name = 0
            }
            struct Panel {}
            extension Panel {
                struct Inner { var name, title: String }
            }
            """
        #expect(!members(of: "Inner", in: source).contains("~name : String"))
        #expect(members(of: "Panel.Inner", in: source) == ["~name : String", "~title : String"])
    }

    @Test("a type nested in a function does not give its types to a member type of its name")
    func sameNameInFunction() {
        let source = """
            struct Holder {
                struct Local { var a, b: String }
                func make() -> Int {
                    struct Local { var a, b: Int }
                    return Local(a: 1, b: 2).a
                }
            }
            """
        #expect(members(of: "Holder.Local", in: source) == ["~a : String", "~b : String"])
    }

    @Test("each #if clause keeps its own type for a name both clauses declare")
    func sameNameInIfClauses() {
        let source = """
            struct Metrics {
                #if os(macOS)
                var width, height: Double
                #else
                var width, height: Float
                #endif
            }
            """
        #expect(members(of: "Metrics", in: source) == [
            "~width : Double", "~height : Double", "~width : Float", "~height : Float"
        ])
    }

    // MARK: - Guards: these pass today, and a fix should keep them passing.

    @Test("a byte-order mark, characters of more than one byte, and CRLF line ends before the type")
    func multibyteAndCRLF() {
        let source = "\u{FEFF}// caf\u{E9} \u{1F600} \u{4E2D}\u{6587}\r\n"
            + "let s = \"\u{1F600}\"\r\n"
            + "struct S {\r\n    var a, b: Int\r\n}\r\n"
        #expect(members(of: "S", in: source) == ["~a : Int", "~b : Int"])
    }

    @Test("both clauses of an #if")
    func ifConfigClauses() {
        let source = """
            struct S {
                #if DEBUG
                var a, b: Int
                #else
                var c, d: String
                #endif
            }
            """
        #expect(members(of: "S", in: source) == ["~a : Int", "~b : Int", "~c : String", "~d : String"])
    }
}
