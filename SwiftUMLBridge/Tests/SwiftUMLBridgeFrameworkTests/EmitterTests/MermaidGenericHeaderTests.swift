import Testing
@testable import SwiftUMLBridgeFramework

/// Mermaid reads a class-body line as an annotation only when the whole line is `<<…>>`, so a
/// generic clause after `<<struct>>` made a member or a garbled annotation. Every `<<` line must be
/// one plain annotation, in each extension mode, with the parameters in the label.
@Suite("Mermaid: a generic type keeps its annotation")
struct MermaidGenericHeaderTests {

    static let modes: [ExtensionVisualization] = [.all, .merged, .none]

    static let source = """
        protocol Shape {}
        struct Stack<Element> { var items: [Element] = [] }
        class Cache<Key> {}
        enum Either<Left, Right> {
            case left(Left)
            case right(Right)
        }
        actor Pool<Resource> {}
        struct Sorted<T: Equatable & Shape> {}
        struct Holder<T: ~Copyable> {}
        struct Lines<T: Collection<String>> {}
        struct Outer<T> { struct Inner<U> {} }
        @MainActor final class Loader<Item> {}
        extension Stack<Int> { func total() -> Int { 0 } }
        """

    private static func lines(_ mode: ExtensionVisualization, generics: Bool = true) -> [String] {
        let elements = ElementOptions(showGenerics: generics, showExtensions: mode)
        let configuration = Configuration(elements: elements, format: .mermaid)
        return ClassDiagramGenerator().generateScript(for: source, with: configuration).text
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// A `<<` line that Mermaid would not read as one annotation with a plain name.
    private static func isPartialAnnotation(_ line: String) -> Bool {
        guard line.hasPrefix("<<") else { return false }
        guard line.hasSuffix(">>") else { return true }
        return line.dropFirst(2).dropLast(2).contains { $0 == "<" || $0 == ">" }
    }

    @Test("every line that starts with `<<` is one whole annotation", arguments: modes)
    func annotationLines(mode: ExtensionVisualization) {
        #expect(Self.lines(mode).filter(Self.isPartialAnnotation) == [])
    }

    @Test("each generic type keeps its kind")
    func kinds() {
        let kinds = Self.lines(.all).filter { $0.hasPrefix("<<") }
        #expect(kinds == [
            "<<protocol>>", "<<struct>>", "<<class>>", "<<enum>>", "<<actor>>", "<<struct>>", "<<struct>>",
            "<<struct>>", "<<struct>>", "<<struct>>", "<<class>>", "<<MainActor>>", "<<extension>>"
        ])
    }

    @Test("the parameters are in the label, as entities")
    func labels() {
        #expect(Self.lines(.all).filter { $0.hasPrefix("class ") } == [
            "class Shape[\"Shape\"] {",
            "class Stack[\"Stack&lt;Element&gt;\"] {",
            "class Cache[\"Cache&lt;Key&gt;\"] {",
            "class Either[\"Either&lt;Left, Right&gt;\"] {",
            "class Pool[\"Pool&lt;Resource&gt;\"] {",
            "class Sorted[\"Sorted&lt;T: Equatable &amp; Shape&gt;\"] {",
            "class Holder[\"Holder&lt;T: ~Copyable&gt;\"] {",
            "class Lines[\"Lines&lt;T: Collection&lt;String&gt;&gt;\"] {",
            "class Outer[\"Outer&lt;T&gt;\"] {",
            "class Outer.Inner[\"Inner&lt;U&gt;\"] {",
            "class Loader[\"Loader&lt;Item&gt;\"] {",
            "class Stack0[\"Stack&lt;Int&gt;\"] {"
        ])
    }

    // MARK: - Guard: this passes today, and a fix should keep it passing.

    @Test("with showGenerics off, no label or line carries a generic clause", arguments: modes)
    func genericsOff(mode: ExtensionVisualization) {
        let lines = Self.lines(mode, generics: false)
        #expect(lines.filter { $0.contains("&lt;") || Self.isPartialAnnotation($0) } == [])
    }
}
