import Testing
@testable import SwiftUMLBridgeFramework

/// With `elements.showNestedTypes: false` the lookup records no nested type, so whether an
/// extension is of a project type goes by the nested types the items do not list
/// (`TypeLookup.unlistedMembers`): an alias's target among them is the project's, and one another
/// file hides is not. Every source passes `swiftc -typecheck`, its files together.
@Suite("An extension written through a hidden nested type is judged as Swift reads it")
struct HiddenNestedAliasScopeTests {

    static let formats: [DiagramFormat] = [.plantuml, .mermaid, .nomnoml, .svg]

    private func script(_ source: String, _ format: DiagramFormat, _ mode: ExtensionVisualization) -> DiagramScript {
        let elements = ElementOptions(showNestedTypes: false, showExtensions: mode)
        let configuration = Configuration(elements: elements, format: format)
        return ClassDiagramGenerator().generateScript(for: source, with: configuration)
    }

    /// The id each supertype edge from `child` ends on, in SVG the members of that node, which
    /// tell the boxes apart.
    private func ends(
        from child: String, _ source: String, _ format: DiagramFormat, _ mode: ExtensionVisualization
    ) -> [String] {
        let drawn = script(source, format, mode)
        switch format {
        case .svg:
            let graph = drawn.layoutGraph
            return graph?.edges.filter { $0.sourceId == child && $0.style != .composition }.map { edge in
                (graph?.nodes.first { $0.id == edge.targetId }?.compartments.flatMap(\.items) ?? []).joined()
            } ?? []
        case .nomnoml:
            return drawn.text.split(separator: "\n").compactMap { line -> String? in
                guard line.hasPrefix("[\(child)] -"), let open = line.lastIndex(of: "[") else { return nil }
                return String(line[line.index(after: open)...].dropLast())
            }
        default:
            return drawn.text.split(separator: "\n").compactMap { line -> String? in
                let words = line.split(separator: " ")
                guard words.count >= 3, ["<|--", "<|.."].contains(words[1]), words[2] == child else { return nil }
                return String(words[0])
            }
        }
    }

    private func classLines(_ source: String) -> [Substring] {
        script(source, .plantuml, .merged).text.split(separator: "\n").filter { $0.hasPrefix("class ") }
    }

    /// Nested types hidden, the lookup records neither `Outer.Inner` nor `Box.Inner.Real`, so an
    /// alias whose target is one of them, `Me = Inner` reached through `Crate = Outer.Me`, or
    /// `Stamp = Real` declared beside it, was followed to a bare `Inner` or `Real`, which the
    /// project does not declare: `Desc` was taken for a member of a type outside the diagram, so
    /// `T` reached no box and `--merge-extensions` split the protocol's extensions in two.
    @Test("an extension spelled through an alias of a hidden nested type is the project's",
          arguments: formats, [
            ("struct Outer { struct Inner {}; typealias Me = Inner }\ntypealias Crate = Outer.Me", "Crate"),
            ("struct Box { struct Inner { struct Real {}; typealias Stamp = Real } }", "Box.Inner.Stamp")
          ])
    func aliasOfHiddenNestedTypeIsTheProjects(format: DiagramFormat, declared: (source: String, extended: String)) {
        let alone = """
            \(declared.source)
            extension \(declared.extended) { typealias Desc = CustomStringConvertible }
            extension \(declared.extended).Desc { func viaAlias() {} }
            struct T: CustomStringConvertible { var description: String { "" } }
            """
        let box = "\(declared.extended).Desc"
        #expect(ends(from: "T", alone, format, .all) == [format == .svg ? "~ viaAlias()" : box])
        let both = alone + "\nextension CustomStringConvertible { func direct() {} }"
        let merged = format == .svg ? "~ viaAlias()~ direct()" : box
        #expect(ends(from: "T", both, format, .merged) == [merged])
        let boxes = classLines(both)
        #expect(boxes.contains { $0.contains("as \(box)") })
        #expect(!boxes.contains { $0.contains("as CustomStringConvertible") })
    }

    /// A.swift's `fileprivate struct FormatStyle` is not seen from B.swift, so
    /// `extension Date.FormatStyle.Symbol` there extends Foundation's type, whose `TimeZone`
    /// member `TZ` may be. Nested types hidden, the type was found among the unlisted members
    /// without its access, so the extension counted as the project's, and `--merge-extensions`
    /// folded `extension TimeZone` into `extension Date.FormatStyle.Symbol.TZ`.
    @Test("a nested type another file hides makes no extension of its name the project's")
    func nestedTypeAnotherFileHidesIsNotTheProjects() throws {
        let files = [
            ("A.swift", "import Foundation\nextension Date { fileprivate struct FormatStyle { struct Symbol {} } }"),
            ("B.swift", """
                import Foundation
                extension Date.FormatStyle.Symbol { typealias TZ = TimeZone }
                extension Date.FormatStyle.Symbol.TZ { func viaMember() {} }
                extension TimeZone { func direct() {} }
                """)
        ]
        let items = try files.flatMap { file in
            let items = try #require(SyntaxStructure.create(from: file.1)?.substructure)
            func stamp(_ item: SyntaxStructure) {
                item.sourceLocation = SourceLocation(filePath: file.0, line: 1, column: 1)
                item.substructure?.forEach(stamp)
            }
            items.forEach(stamp)
            return items
        }
        let elements = ElementOptions(showNestedTypes: false, showExtensions: .merged)
        let text = DiagramScript(items: items, configuration: Configuration(elements: elements, format: .plantuml)).text
        #expect(text.split(separator: "\n").contains { $0.hasPrefix("class \"TimeZone\" as TimeZone ") })
    }
}
