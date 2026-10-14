import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// The SVG class diagram and `deps --types` name `extension Foo<Int>` and `extension [Int]` after
/// the type they extend, `Foo` and `Array`, as they name `extension Foo where T == Int` (#66).
@Suite("SVG and deps: extension of a bound generic type")
struct BoundGenericExtensionModelTests {

    private func svg(_ source: String, _ extensions: ExtensionVisualization) -> LayoutGraph? {
        let configuration = Configuration(elements: ElementOptions(showExtensions: extensions), format: .svg)
        return ClassDiagramGenerator().generateScript(for: source, with: configuration).layoutGraph
    }

    @Test("the extension's node is a second Foo, and a type nested in it hangs off Foo")
    func svgNodesAndEdges() {
        let source = "struct Foo<T> {}\nextension Foo<Int> { struct Inner {} }"
        #expect(svg(source, .all)?.nodeIds == ["Foo", "Foo.Inner", "Foo_1"])
        #expect(svg(source, .all)?.edgeEnds == ["Foo -> Foo.Inner"])
        #expect(svg(source, .none)?.edgeEnds == ["Foo -> Foo.Inner"])
    }

    @Test("deps --types draws a bound extension's conformance from the type it extends")
    func dependencyEdgesUseTheBaseName() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoundGenericExtensionModelTests-\(UUID().uuidString)")
            .appendingPathExtension("swift")
        let source = "protocol P {}\nstruct Foo<T> {}\nextension Foo<Int>: P {}\nextension [Int]: P {}"
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let edges = DependencyGraphGenerator().extractEdges(for: [url.path], mode: .types)
        #expect(edges.map { "\($0.from) -> \($0.to)" } == ["Foo -> P", "Array -> P"])
    }
}
