import Testing
@testable import SwiftUMLBridgeFramework

/// A protocol nested in a type (SE-0404, Swift 5.10), `enum Outer { protocol Shape {} }`, is a
/// nested type like any other: it gets a box of its own under the id `Outer.Shape`, it hangs off
/// the type it is nested in, and a conformance that names it in full ends on that box with the
/// conformance arrow, with extensions shown, merged or hidden.
@Suite("A protocol nested in a type is drawn")
struct NestedProtocolTests {

    static let formats: [DiagramFormat] = [.plantuml, .mermaid, .nomnoml, .svg]
    static let modes: [ExtensionVisualization] = [.all, .merged, .none]

    static let shapes = """
        enum Outer {
            protocol Shape {}
        }
        struct Square: Outer.Shape {}
        """

    static let delegate = """
        protocol Delegate: AnyObject {
            var rowCount: Int { get }
            func didSelect(row: Int)
        }
        """

    private func lines(_ drawn: DiagramScript) -> [String] {
        drawn.text.split(separator: "\n").map(String.init)
    }

    /// The ids the diagram declares a protocol under, in drawing order.
    private func protocolIds(_ drawn: DiagramScript) -> [String] {
        let lines = lines(drawn)
        switch drawn.format {
        case .svg:
            return drawn.layoutGraph?.nodes.filter { $0.stereotype == "protocol" }.map(\.id) ?? []
        case .plantuml:
            // `class "Shape" as Outer.Shape << (P, goldenRod) protocol >> {`
            return lines.filter { $0.hasPrefix("class ") && $0.contains(" protocol >>") }.compactMap { line in
                line.components(separatedBy: " as ").last?.split(separator: " ").first.map(String.init)
            }
        case .mermaid:
            // `class Outer.Shape["Shape"] {`, then `<<protocol>>` on the next line.
            return zip(lines, lines.dropFirst()).compactMap { header, next in
                guard header.hasPrefix("class "), next.trimmingCharacters(in: .whitespaces) == "<<protocol>>",
                      let open = header.firstIndex(of: "[") else { return nil }
                return String(header[header.index(header.startIndex, offsetBy: 6)..<open])
            }
        case .nomnoml:
            // `[<interface id=Outer.Shape> Shape]`
            let prefix = "[<interface id="
            return lines.compactMap { line in
                guard line.hasPrefix(prefix), let close = line.firstIndex(of: ">") else { return nil }
                return String(line[line.index(line.startIndex, offsetBy: prefix.count)..<close])
            }
        }
    }

    /// Whether `drawn` draws `child`'s conformance to the protocol declared as `protocolId`.
    private func conforms(_ child: String, to protocolId: String, in drawn: DiagramScript) -> Bool {
        switch drawn.format {
        case .svg:
            return drawn.layoutGraph?.edges.contains {
                $0.sourceId == child && $0.targetId == protocolId && $0.style != .composition
            } ?? false
        case .nomnoml:
            return lines(drawn).contains("[\(child)] --:> conforms to [\(protocolId)]")
        default:
            return lines(drawn).contains("\(protocolId) <|.. \(child) : conforms to")
        }
    }

    /// Whether `drawn` hangs `child` off `parent`. Mermaid draws no nesting edge.
    private func nests(_ child: String, in parent: String, _ drawn: DiagramScript) -> Bool {
        switch drawn.format {
        case .svg:
            return drawn.layoutGraph?.edges.contains {
                $0.sourceId == parent && $0.targetId == child && $0.style == .composition
            } ?? false
        case .nomnoml:
            return lines(drawn).contains("[\(parent)] +- [\(child)]")
        default:
            return lines(drawn).contains("\(parent) +-- \(child)")
        }
    }

    /// Each format and extension mode, as `"<format> <mode>"`, for which `check` fails.
    private func misses(
        formats: [DiagramFormat] = NestedProtocolTests.formats, _ check: (DiagramFormat, ExtensionVisualization) -> Bool
    ) -> [String] {
        formats.flatMap { format in
            Self.modes.compactMap { mode in check(format, mode) ? nil : "\(format) \(mode)" }
        }
    }

    @Test("is declared under its qualified name: in an enum, in an extension, and two levels down", arguments: [
        (shapes, "Outer.Shape"),
        ("enum Outer {}\nextension Outer {\n    protocol Drawable {}\n}", "Outer.Drawable"),
        ("enum A {\n    enum B {\n        protocol Deep {}\n    }\n}", "A.B.Deep")
    ])
    func declared(source: String, id: String) {
        #expect(misses { protocolIds(classDiagram(source, $0, $1)) == [id] } == [])
    }

    @Test("a conformance written in full ends on its box, with the conformance arrow")
    func conformanceInFull() {
        #expect(misses { conforms("Square", to: "Outer.Shape", in: classDiagram(Self.shapes, $0, $1)) } == [])
    }

    @Test("hangs off the type it is nested in")
    func nestingEdge() {
        let deep = "enum A {\n    enum B {\n        protocol Deep {}\n    }\n}"
        #expect(misses(formats: [.plantuml, .nomnoml, .svg]) {
            nests("Outer.Shape", in: "Outer", classDiagram(Self.shapes, $0, $1))
                && nests("A.B.Deep", in: "A.B", classDiagram(deep, $0, $1))
        } == [])
    }

    @Test("lists its requirements and draws its own supertype as a top-level protocol does", arguments: formats)
    func likeTopLevel(format: DiagramFormat) throws {
        let topLevel = classDiagram(Self.delegate, format)
        let nested = classDiagram("class TableView {\n\(Self.delegate)\n}", format)
        if format == .svg {
            let top = try #require(topLevel.layoutGraph?.nodes.first { $0.id == "Delegate" })
            let inner = try #require(nested.layoutGraph?.nodes.first { $0.id == "TableView.Delegate" })
            #expect(inner.label == top.label)
            #expect(inner.stereotype == top.stereotype)
            #expect(inner.compartments.map(\.items) == top.compartments.map(\.items))
            return
        }
        // The edge to `AnyObject`, which neither diagram declares, with the id swapped.
        let edge = { (drawn: DiagramScript) in self.lines(drawn).filter { $0.contains("AnyObject") } }
        let expected = edge(topLevel).map {
            $0.replacingOccurrences(of: "[Delegate]", with: "[TableView.Delegate]")
                .replacingOccurrences(of: " Delegate", with: " TableView.Delegate")
        }
        #expect(!expected.isEmpty)
        #expect(edge(nested) == expected)
    }

    @Test("an extension of it is linked to it when shown, and merged into it when merged")
    func extended() throws {
        let source = Self.shapes + "\nextension Outer.Shape {\n    func describe() -> String { \"shape\" }\n}"
        #expect(lines(classDiagram(source, .plantuml, .all)).contains("Outer.Shape <.. Outer.Shape0 : ext"))
        let merged = try #require(classDiagram(source, .svg, .merged).layoutGraph)
        #expect(merged.nodes.map(\.id).sorted() == ["Outer", "Outer.Shape", "Square"])
        let box = try #require(merged.nodes.first { $0.id == "Outer.Shape" })
        #expect(box.stereotype == "protocol")
        #expect(box.compartments.flatMap(\.items).contains { $0.contains("describe") })
    }

    /// `isNestedType` is derived from `ElementKind.processable`, so a kind added there is walked
    /// into too; only `.macro`, declared at the top level alone, keeps its place after the types.
    @Test("every drawn kind but a macro is walked into for nested types")
    func nestedKindsFollowProcessable() {
        let items: [SyntaxStructure] = []
        let walked = ElementKind.processable.filter { items.isNestedType(SyntaxStructure(kind: $0, name: "T")) }
        #expect(walked == ElementKind.processable.filter { $0 != .macro })
        #expect(walked.contains(.protocol))
    }

    // MARK: - Guards: these pass today, and a fix should keep them passing.

    @Test("a fileprivate one is hidden by default, as a fileprivate protocol at top level is")
    func hiddenByAccessLevel() {
        let source = "enum Outer {\n    fileprivate protocol Secret {}\n}\nfileprivate protocol TopSecret {}"
        #expect(misses { protocolIds(classDiagram(source, $0, $1)) == [] } == [])
    }

    @Test("showNestedTypes: false leaves it out, as it leaves out every nested type")
    func nestedTypesOff() {
        #expect(misses { protocolIds(classDiagram(Self.shapes, $0, $1, nestedTypes: false)) == [] } == [])
    }
}
