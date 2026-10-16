import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// Under `showExtensions: .merged`, the SVG class diagram draws the supertypes an extension's
/// inheritance clause names from the box its members are merged into, each looked up from where
/// the extension is written, and each once per protocol it ends on (#76).
@Suite("Merged extensions — the conformances they declare, in SVG")
struct MergedExtensionConformanceSVGTests {

    private static func graph(_ source: String, _ mode: ExtensionVisualization = .merged) -> LayoutGraph? {
        let configuration = Configuration(elements: ElementOptions(showExtensions: mode), format: .svg)
        return ClassDiagramGenerator().generateScript(for: source, with: configuration).layoutGraph
    }

    /// Each edge as `"<source id> -> <target id> <style>"`.
    private static func styledEdges(_ graph: LayoutGraph?) -> [String] {
        graph?.edges.map { "\($0.sourceId) -> \($0.targetId) \($0.style)" } ?? []
    }

    /// The SVG graph for `files`, each written to its own file, with extensions merged and types
    /// of every access level drawn.
    private static func graph(files: [String: String]) throws -> LayoutGraph? {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MergedExtensionConformanceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = try files.sorted { $0.key < $1.key }.map { name, source in
            let url = root.appendingPathComponent(name)
            try source.write(to: url, atomically: true, encoding: .utf8)
            return url.path
        }
        let elements = ElementOptions(
            havingAccessLevel: [.open, .public, .package, .internal, .fileprivate, .private], showExtensions: .merged
        )
        return ClassDiagramGenerator()
            .generateScript(for: paths, with: Configuration(elements: elements, format: .svg)).layoutGraph
    }

    @Test("SVG draws an empty extension's conformance from the type, once")
    func svgEmptyExtension() {
        let source = "protocol P {}\nstruct Foo {}\nextension Foo: P {}"
        #expect(Self.styledEdges(Self.graph(source, .all)) == ["Foo_1 -> P dependency"])
        #expect(Self.styledEdges(Self.graph(source)) == ["Foo -> P inheritance"])
    }

    /// SVG draws no edge to a type the diagram does not declare, such as `Codable`, from a type's
    /// own clause either, so only the pairs that declare `P` must draw one.
    @Test("SVG draws a merged conformance exactly as the type's own clause draws it")
    func svgDrawnLikeOwnClause() {
        for (merged, own) in MergedExtensionConformanceTests.sameAsOwnClause {
            #expect(Self.styledEdges(Self.graph(merged)) == Self.styledEdges(Self.graph(own)), "\(merged)")
            if merged.hasPrefix("protocol P") {
                #expect(!Self.styledEdges(Self.graph(merged)).isEmpty, "\(merged)")
            }
        }
    }

    @Test("SVG keeps a superclass, draws each part of a composition, and draws a shared conformance once")
    func svgShapes() {
        let source = """
            class Base {}
            protocol P {}
            protocol Q {}
            protocol R {}
            class Sub: Base {}
            extension Sub: P & Q {}
            #if DEBUG
            extension Sub: R {}
            #else
            extension Sub: R {}
            #endif
            """
        #expect(Self.graph(source)?.edgeEnds == ["Sub -> Base", "Sub -> P", "Sub -> Q", "Sub -> R"])
    }

    @Test("SVG draws a conformance two types each carry from each box")
    func svgTwoTypesCarryOneProtocol() {
        let source = "protocol P {}\nstruct A {}\nstruct B {}\nextension A: P {}\nextension B: P {}"
        #expect(Self.graph(source)?.edgeEnds == ["A -> P", "B -> P"])
    }

    @Test("SVG draws every conformance of a type the sources only extend from its one box")
    func svgUndeclaredExtendedType() {
        let source = "protocol P {}\nprotocol Q {}\nextension String: P {}\nextension String: Q {}"
        #expect(Self.styledEdges(Self.graph(source)) == ["String -> P dependency", "String -> Q dependency"])
    }

    @Test("SVG looks a merged conformance up where its extension is written, not where the type is")
    func svgLooksUpFromTheExtension() throws {
        let graph = try Self.graph(files: [
            "A.swift": "struct Foo {}\nfileprivate protocol P {}",
            "B.swift": "fileprivate protocol P {}\nextension Foo: P {}"
        ])
        let nodes = graph?.nodes.map { "\($0.id) \($0.sourceLocation?.filePath.split(separator: "/").last ?? "")" }
        #expect(nodes == ["P A.swift", "P_1 B.swift", "Foo A.swift"])
        #expect(graph?.edgeEnds == ["Foo -> P_1"])
    }

    @Test("SVG draws two same-named protocols that two files declare, one edge to each")
    func svgSameNameInTwoFiles() throws {
        let ownAndCarried = try Self.graph(files: [
            "A.swift": "fileprivate protocol P {}\nstruct Foo: P {}",
            "B.swift": "fileprivate protocol P {}\nextension Foo: P {}"
        ])
        #expect(ownAndCarried?.edgeEnds == ["Foo -> P", "Foo -> P_1"])
        let twoCarried = try Self.graph(files: [
            "A.swift": "struct Foo {}",
            "B.swift": "fileprivate protocol P {}\nextension Foo: P {}",
            "C.swift": "fileprivate protocol P {}\nextension Foo: P {}"
        ])
        #expect(twoCarried?.edgeEnds == ["Foo -> P", "Foo -> P_1"])
    }

    @Test("SVG draws one edge for a conformance an #if splits across two files")
    func svgIfAcrossFiles() throws {
        let graph = try Self.graph(files: [
            "A.swift": "protocol P {}\nstruct Foo {}",
            "B.swift": "#if DEBUG\nextension Foo: P {}\n#endif",
            "C.swift": "#if !DEBUG\nextension Foo: P {}\n#endif"
        ])
        #expect(graph?.edgeEnds == ["Foo -> P"])
    }

    /// A hand-built declaration in `file`, in `module`.
    private static func declared(
        _ kind: ElementKind, _ name: String, in file: String, module: String,
        access: ElementAccessibility? = nil, inheriting parents: [String] = []
    ) -> SyntaxStructure {
        let item = SyntaxStructure(
            accessibility: access, inheritedTypes: parents.map { SyntaxStructure(name: $0) }, kind: kind, name: name
        )
        item.sourceLocation = SourceLocation(filePath: file, line: 1, column: 1)
        item.module = module
        return item
    }

    @Test("SVG looks a merged conformance up in its extension's module, not the type's")
    func svgLooksUpFromTheExtensionsModule() {
        let items = [
            Self.declared(.struct, "Foo", in: "A.swift", module: "Core", access: .public),
            Self.declared(.protocol, "P", in: "A.swift", module: "Core", access: .public),
            Self.declared(.protocol, "P", in: "B.swift", module: "Ext"),
            Self.declared(.extension, "Foo", in: "C.swift", module: "Ext", inheriting: ["P"])
        ]
        let configuration = Configuration(elements: ElementOptions(showExtensions: .merged), format: .svg)
        let graph = LayoutGraphBuilder.buildClassDiagram(from: items, configuration: configuration)
        #expect(graph.nodes.map { "\($0.id) \($0.module ?? "")" } == ["P Core", "P_1 Ext", "Foo Core"])
        #expect(graph.edgeEnds == ["Foo -> P_1"])
    }

    @Test("SVG hides a merged conformance that realize.exclude matches")
    func svgExcluded() {
        let source = "protocol P {}\nprotocol Q {}\nstruct Foo {}\nextension Foo: P, Q {}"
        let configuration = Configuration(
            elements: ElementOptions(showExtensions: .merged),
            relationships: RelationshipOptions(realize: Relationship(label: "conforms to", exclude: ["Q"])),
            format: .svg
        )
        let graph = ClassDiagramGenerator().generateScript(for: source, with: configuration).layoutGraph
        #expect(graph?.edgeEnds == ["Foo -> P"])
    }
}
