import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// A type written across lines is the type written on one line: `Swift` then `.Equatable` on the
/// next line is `Swift.Equatable`. The builder named it `"Swift\n    .Equatable"`, which split the
/// PlantUML and Mermaid edge over two lines, failed the whole Mermaid class diagram, sent `deps`
/// edges to a `Swift` box and lost SVG edges to declared types (#155). Each test compares a source
/// with the same source on one line, the control.
@Suite("A type written across lines is read as it is on one line")
struct MultilineTypeNameTests {
    static let split = """
        protocol Shape {}
        struct Circle: Swift
            .Equatable, Shape {}
        struct Square {}
        extension Square: Swift
            .Hashable {}
        enum Outer {
            class Base {}
        }
        class Sub: Outer
            .Base {}
        class Generic<T> {}
        class Concrete: Generic<
            Int
        > {}
        struct Pair: Equatable
            & Sendable {}
        struct Box<T: Swift
            .Equatable> {
            var value: T
        }
        """

    static let oneLine = """
        protocol Shape {}
        struct Circle: Swift.Equatable, Shape {}
        struct Square {}
        extension Square: Swift.Hashable {}
        enum Outer {
            class Base {}
        }
        class Sub: Outer.Base {}
        class Generic<T> {}
        class Concrete: Generic<Int> {}
        struct Pair: Equatable & Sendable {}
        struct Box<T: Swift.Equatable> {
            var value: T
        }
        """

    /// Attributes, bound extension arguments and property types, the builder's other type reads.
    static let splitMembers = """
        @Observation
            .Observable
        final class Model {
            var count: Swift
                .Int
            var handler: (
                Int,
                String
            ) -> Void
            var low, high: Swift
                .Int
        }
        extension Array<Swift
            .Int> {
            func total() -> Int { 0 }
        }
        """

    static let oneLineMembers = """
        @Observation.Observable
        final class Model {
            var count: Swift.Int
            var handler: (Int, String) -> Void
            var low, high: Swift.Int
        }
        extension Array<Swift.Int> {
            func total() -> Int { 0 }
        }
        """

    /// Each top-level declaration's supertypes and generic constraints, as `Name: supertype`.
    private func supertypes(_ source: String) -> [String] {
        (SyntaxStructure.create(from: source)?.substructure ?? []).flatMap { item in
            let own = (item.inheritedTypes ?? []).compactMap(\.name)
            let constraints = (item.substructure ?? []).filter { $0.kind == .genericTypeParam }
                .flatMap { ($0.inheritedTypes ?? []).compactMap(\.name) }
            return (own + constraints).map { "\(item.name ?? "?"): \($0)" }
        }
    }

    private func classDiagram(_ source: String, _ format: DiagramFormat) -> DiagramScript {
        ClassDiagramGenerator().generateScript(for: source, with: Configuration(format: format))
    }

    private func deps(_ source: String, _ format: DiagramFormat) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("multiline-type-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try source.write(to: dir.appendingPathComponent("Shapes.swift"), atomically: true, encoding: .utf8)
        return DependencyGraphGenerator()
            .generateScript(for: [dir.path], mode: .types, with: Configuration(format: format)).text
    }

    @Test("each supertype and constraint is named as on one line")
    func names() {
        let control = supertypes(Self.oneLine)
        #expect(control == [
            "Circle: Swift.Equatable", "Circle: Shape", "Square: Swift.Hashable", "Sub: Outer.Base",
            "Concrete: Generic<Int>", "Pair: Equatable", "Pair: Sendable", "Box: Swift.Equatable"
        ])
        #expect(supertypes(Self.split) == control)
    }

    @Test("the class diagram is the one-line source's", arguments: [DiagramFormat.plantuml, .mermaid, .nomnoml])
    func classText(format: DiagramFormat) {
        #expect(classDiagram(Self.split, format).text == classDiagram(Self.oneLine, format).text)
    }

    @Test("attributes, extension arguments and property types read as on one line",
          arguments: [DiagramFormat.plantuml, .mermaid, .nomnoml])
    func memberText(format: DiagramFormat) {
        let observed = classDiagram(Self.splitMembers, format).text
        let control = classDiagram(Self.oneLineMembers, format).text
        #expect(observed == control)
        if format == .plantuml {
            #expect(control.contains("~low : Swift.Int"), "\(control)")
            #expect(control.contains("~handler : (Int, String) -> Void"), "\(control)")
        }
    }

    @Test("the SVG class diagram draws the same edges")
    func svgEdges() {
        func edges(_ source: String) -> [String] {
            (classDiagram(source, .svg).layoutGraph?.edges ?? []).map { "\($0.sourceId) -> \($0.targetId)" }.sorted()
        }
        let control = edges(Self.oneLine)
        #expect(control.contains("Sub -> Outer.Base"))
        #expect(edges(Self.split) == control)
    }

    @Test("deps --types is the one-line source's", arguments: [DiagramFormat.plantuml, .mermaid, .nomnoml, .svg])
    func depsText(format: DiagramFormat) throws {
        #expect(try deps(Self.split, format) == deps(Self.oneLine, format))
    }

    @Test("--exclude matches a supertype written across lines")
    func depsExclude() throws {
        let configuration = Configuration(elements: ElementOptions(exclude: ["Swift.*"]), format: .plantuml)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("multiline-exclude-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.split.write(to: dir.appendingPathComponent("Shapes.swift"), atomically: true, encoding: .utf8)
        let text = DependencyGraphGenerator().generateScript(for: [dir.path], mode: .types, with: configuration).text
        #expect(!text.contains("Swift"), "\(text)")
        #expect(text.contains("Circle --> Shape"), "\(text)")
    }

    // MARK: - The joining rule

    @Test("a break is dropped beside . ( [ < and before ) ] > , and is a space elsewhere", arguments: [
        ("Swift\n    .Equatable", "Swift.Equatable"),
        ("Generic<\n    Int,\n    String\n>", "Generic<Int, String>"),
        ("(\n    Int,\n    String\n) -> Void", "(Int, String) -> Void"),
        ("[\n    String: Int\n]", "[String: Int]"),
        ("Equatable\n    & Sendable", "Equatable & Sendable"),
        ("Swift\n    .`Equatable`", "Swift.Equatable")
    ])
    func joins(written: String, read: String) {
        #expect(written.singleLineTypeName == read)
    }

    @Test("a comment in a break goes with it; a comment within a line stays", arguments: [
        ("Swift // the standard library's\n    .Equatable", "Swift.Equatable"),
        ("Swift /* the\n standard library */ .Equatable", "Swift.Equatable"),
        ("Swift /* stdlib */ .Hashable", "Swift /* stdlib */ .Hashable")
    ])
    func comments(written: String, read: String) {
        #expect(written.singleLineTypeName == read)
    }

    @Test("text on one line reads as it does today")
    func oneLineUnchanged() throws {
        let structure = try #require(SyntaxStructure.create(from: """
            struct Holder {
                var pairs: Dictionary<Int, String>
                var callback: (Int, String) -> Void
                var tagged: [/* ids */ Int]
            }
            """))
        let members = try #require(structure.substructure?.first?.substructure)
        #expect(members.map(\.typename) == ["Dictionary<Int, String>", "(Int, String) -> Void", "[/* ids */ Int]"])
    }

    @Test("a line break between supertypes, or after the colon, is not part of a name")
    func breakBetweenSupertypes() {
        let observed = supertypes("""
            protocol Shape {}
            struct Circle:
                Swift.Equatable,
                Shape {}
            """)
        #expect(observed == ["Circle: Swift.Equatable", "Circle: Shape"])
    }
}
