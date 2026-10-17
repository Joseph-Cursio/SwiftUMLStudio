import Testing
@testable import SwiftUMLBridgeFramework

@Suite("SequenceScript — Mermaid")
struct SequenceMermaidTests {

    private func makeEdges() -> [CallEdge] {
        // swiftlint:disable line_length
        [
            CallEdge(callerType: "Foo", callerMethod: "run", calleeType: "Bar", calleeMethod: "process", isAsync: false, isUnresolved: false),
            CallEdge(callerType: "Foo", callerMethod: "run", calleeType: "Bar", calleeMethod: "finish", isAsync: true, isUnresolved: false),
            CallEdge(callerType: "Foo", callerMethod: "run", calleeType: nil, calleeMethod: "unknownClosure", isAsync: false, isUnresolved: true)
        ]
        // swiftlint:enable line_length
    }

    private func makeScript(edges: [CallEdge] = []) -> SequenceScript {
        var config = Configuration.default
        config.format = .mermaid
        return SequenceScript(
            traversedEdges: edges,
            entryType: "Foo",
            entryMethod: "run",
            configuration: config
        )
    }

    @Test("starts with sequenceDiagram")
    func startsWithSequenceDiagram() {
        let script = makeScript(edges: makeEdges())
        #expect(script.text.hasPrefix("sequenceDiagram"))
    }

    @Test("does not contain @startuml")
    func noStartuml() {
        let script = makeScript(edges: makeEdges())
        #expect(script.text.contains("@startuml") == false)
    }

    @Test("contains %% title comment")
    func titleCommentPresent() {
        let script = makeScript(edges: makeEdges())
        #expect(script.text.contains("%% title: Foo.run"))
    }

    @Test("participant lines present")
    func participantLinesPresent() {
        let script = makeScript(edges: makeEdges())
        #expect(script.text.contains("participant Foo"))
        #expect(script.text.contains("participant Bar"))
    }

    @Test("sync call ->> present")
    func syncArrowPresent() {
        let script = makeScript(edges: makeEdges())
        #expect(script.text.contains("Foo->>Bar: process()"))
    }

    @Test("async call -->> present")
    func asyncArrowPresent() {
        let script = makeScript(edges: makeEdges())
        #expect(script.text.contains("Foo-->>Bar: finish()"))
    }

    @Test("unresolved emits a Note right of its caller")
    func unresolvedNotePresent() {
        let script = makeScript(edges: makeEdges())
        #expect(script.text.contains("Note right of Foo: Unresolved: unknownClosure()"))
    }

    @Test("empty edges produces minimal valid diagram")
    func emptyEdgesValid() {
        let script = makeScript(edges: [])
        #expect(script.text.contains("sequenceDiagram"))
        #expect(script.text.contains("%% title: Foo.run"))
    }

    @Test("format property is mermaid")
    func formatIsMermaid() {
        let script = makeScript(edges: makeEdges())
        #expect(script.format == .mermaid)
    }

    @Test("encodeText decodes back to exactly the script")
    func encodeTextRoundTrips() {
        let script = makeScript(edges: makeEdges())
        #expect(PlantUMLTextDecoding.decode(script.encodeText()) == script.text)
    }
}
