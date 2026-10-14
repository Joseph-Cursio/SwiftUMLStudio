import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// `extension Foo<Int>` is shorthand for `extension Foo where T == Int` (SE-0361), and `[Int]`,
/// `[String: Int]` and `Int?` for `Array`, `Dictionary` and `Optional` with the same kind of
/// constraint. Sequence, activity and state diagrams name the extended type as they do for the
/// `where` spelling: by its base name (#66).
@Suite("Call graph: extension of a bound generic type")
struct BoundGenericExtensionCallGraphTests {

    /// Each bound or sugared spelling, opening an extension body, beside the `where` spelling it
    /// is shorthand for.
    static let spellings: [(bound: String, constrained: String)] = [
        ("struct Foo<T> {}\nextension Foo<Int> {", "struct Foo<T> {}\nextension Foo where T == Int {"),
        ("struct Foo<T> {}\nextension Foo<Swift.Int> {", "struct Foo<T> {}\nextension Foo where T == Swift.Int {"),
        ("extension [Int] {", "extension Array where Element == Int {"),
        ("extension [String: Int] {", "extension Dictionary where Key == String, Value == Int {"),
        ("extension Int? {", "extension Optional where Wrapped == Int {")
    ]

    static let body = "\n    func run() { Bar.go() }\n}\nstruct Bar { static func go() {} }"

    @Test("methods and call edges are those of the `where` spelling", arguments: spellings)
    func matchesConstrainedSpelling(bound: String, constrained: String) {
        let boundResult = CallGraphExtractor.extract(from: bound + Self.body)
        let constrainedResult = CallGraphExtractor.extract(from: constrained + Self.body)
        #expect(boundResult.methods == constrainedResult.methods)
        #expect(boundResult.edges == constrainedResult.edges)
    }

    @Test("the listed entry point, split as the CLI and Studio split it, finds the activity body",
          arguments: spellings.map(\.bound))
    func activityFindsListedEntryPoint(bound: String) throws {
        let source = bound + Self.body
        let entry = try #require(CallGraphExtractor.extract(from: source).methods.first { $0.hasSuffix(".run") })
        let parts = entry.split(separator: ".").map(String.init)
        try #require(parts.count == 2, "\(entry)")
        #expect(ActivityFlowExtractor.extract(from: source, entryType: parts[0], entryMethod: parts[1]) != nil)
    }

    @Test("the Mermaid sequence diagram from the listed entry point names the extended type")
    func mermaidSequenceParticipant() throws {
        let source = "struct Foo<T> {}\nextension Foo<Int> {" + Self.body
        let result = CallGraphExtractor.extract(from: source)
        let entry = try #require(result.methods.first { $0.hasSuffix(".run") })
        let parts = entry.split(separator: ".").map(String.init)
        let edges = CallGraph(edges: result.edges).traverse(from: parts[0], entryMethod: parts[1], maxDepth: 3)
        let script = SequenceScript(
            traversedEdges: edges, entryType: parts[0], entryMethod: parts[1],
            configuration: Configuration(format: .mermaid)
        )
        // Mermaid's sequence grammar takes no `<` in a participant (`Expecting 'ACTOR', got 'INVALID'`).
        #expect(script.text.contains("participant Foo\n"), "\(script.text)")
        #expect(script.text.contains("Foo->>Bar: go()"), "\(script.text)")
    }

    /// The SVG participant's location is looked up by the name the class diagram gives the
    /// extension, so the call graph must name it the same way.
    @Test("each SVG sequence participant keeps its source location", arguments: spellings.map(\.bound))
    func sequenceParticipantLocation(bound: String) throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("swift")
        try (bound + Self.body).write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let generator = SequenceDiagramGenerator()
        let entry = try #require(generator.findEntryPoints(for: [url.path]).first { $0.hasSuffix(".run") })
        let parts = entry.split(separator: ".").map(String.init)
        try #require(parts.count == 2, "\(entry)")
        let script = generator.generateScript(
            for: [url.path], entryType: parts[0], entryMethod: parts[1], with: Configuration(format: .svg)
        )
        let participants = try #require(script.sequenceLayout?.participants)
        #expect(participants.map(\.name) == [parts[0], "Bar"])
        #expect(participants.allSatisfy { $0.sourceLocation != nil }, "\(participants.map(\.name))")
    }

    @Test("a call on a specialised type is followed into its extension")
    func specialisedReceiverIsFollowed() {
        let source = """
        struct Bar { static func go() { Foo<Int>.make() } }
        struct Foo<T> {}
        extension Foo<Int> { static func make() { Baz.hit() } }
        struct Baz { static func hit() {} }
        """
        let edges = CallGraph(edges: CallGraphExtractor.extract(from: source).edges)
            .traverse(from: "Bar", entryMethod: "go", maxDepth: 3)
        let described = edges.map { "\($0.callerType).\($0.callerMethod)->\($0.calleeType ?? "?").\($0.calleeMethod)" }
        #expect(described == ["Bar.go->Foo.make", "Foo.make->Baz.hit"])
    }

    @Test("a specialised receiver resolves to its base type; other receivers are unchanged", arguments: [
        ("Foo<Int>.make()", "Foo"),
        ("Foo<Int>().run()", "Foo"),
        ("Swift.Array<Int>.helper()", "Swift.Array"),
        ("Foo.make()", "Foo"),
        ("Foo().run()", "Foo"),
        ("Foo.Bar.make()", "Foo.Bar")
    ])
    func specialisedReceiver(call: String, calleeType: String) {
        // The member call is the first edge; `Foo()` adds one of its own for the initialiser.
        let edges = CallGraphExtractor.extract(from: "struct Caller { func go() { \(call) } }").edges
        #expect(edges.first?.calleeType == calleeType)
    }

    @Test("a state machine driven from the extension is found on its type")
    func stateMachineHost() {
        let lamp = """
        enum Light { case red, green }
        struct Lamp<T> { var state: Light = .red }
        %@ {
            mutating func advance() {
                switch self.state {
                case .red: self.state = .green
                case .green: self.state = .red
                }
            }
        }
        """
        func models(opening header: String) -> [StateMachineModel] {
            StateMachineExtractor.extract(from: lamp.replacingOccurrences(of: "%@", with: header))
        }
        let bound = models(opening: "extension Lamp<Int>")
        let constrained = models(opening: "extension Lamp where T == Int")
        #expect(bound.map(\.hostType) == constrained.map(\.hostType))
        #expect(bound.map(\.transitions.count) == constrained.map(\.transitions.count))
    }
}
