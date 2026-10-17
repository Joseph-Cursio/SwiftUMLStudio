import Testing
@testable import SwiftUMLBridgeFramework

@Suite("SequenceScript — PlantUML")
struct SequencePlantUMLTests {

    private func makeEdges() -> [CallEdge] {
        // swiftlint:disable line_length
        [
            CallEdge(callerType: "Foo", callerMethod: "run", calleeType: "Bar", calleeMethod: "process", isAsync: false, isUnresolved: false),
            CallEdge(callerType: "Foo", callerMethod: "run", calleeType: "Bar", calleeMethod: "finish", isAsync: true, isUnresolved: false),
            CallEdge(callerType: "Foo", callerMethod: "run", calleeType: nil, calleeMethod: "unknownClosure", isAsync: false, isUnresolved: true)
        ]
        // swiftlint:enable line_length
    }

    private func makeScript(edges: [CallEdge] = [], format: DiagramFormat = .plantuml) -> SequenceScript {
        var config = Configuration.default
        config.format = format
        return SequenceScript(
            traversedEdges: edges,
            entryType: "Foo",
            entryMethod: "run",
            configuration: config
        )
    }

    @Test("starts with @startuml")
    func startsWithStartuml() {
        let script = makeScript(edges: makeEdges())
        #expect(script.text.hasPrefix("@startuml"))
    }

    @Test("ends with @enduml")
    func endsWithEnduml() {
        let script = makeScript(edges: makeEdges())
        let lastLine = script.text.components(separatedBy: "\n").last(where: { !$0.isEmpty })
        #expect(lastLine == "@enduml")
    }

    @Test("contains title line")
    func containsTitleLine() {
        let script = makeScript(edges: makeEdges())
        #expect(script.text.contains("title Foo.run"))
    }

    @Test("participant lines present for all types")
    func participantLinesPresent() {
        let script = makeScript(edges: makeEdges())
        #expect(script.text.contains("participant Foo"))
        #expect(script.text.contains("participant Bar"))
    }

    @Test("sync call arrow -> present")
    func syncArrowPresent() {
        let script = makeScript(edges: makeEdges())
        #expect(script.text.contains("Foo -> Bar : process()"))
    }

    @Test("async call arrow ->> present")
    func asyncArrowPresent() {
        let script = makeScript(edges: makeEdges())
        #expect(script.text.contains("Foo ->> Bar : finish()"))
    }

    @Test("unresolved emits a note right of its caller")
    func unresolvedNotePresent() {
        let script = makeScript(edges: makeEdges())
        #expect(script.text.contains("note right of Foo: Unresolved: unknownClosure()"))
    }

    @Test("empty edges produces minimal valid diagram")
    func emptyEdgesValid() {
        let script = makeScript(edges: [])
        #expect(script.text.contains("@startuml"))
        #expect(script.text.contains("@enduml"))
        #expect(script.text.contains("title Foo.run"))
    }

    @Test("Mermaid config is not output for PlantUML format")
    func noMermaidInPlantUML() {
        let script = makeScript(edges: makeEdges())
        #expect(script.text.contains("sequenceDiagram") == false)
    }

    @Test("format property is plantuml")
    func formatIsPlantuml() {
        let script = makeScript(edges: makeEdges())
        #expect(script.format == .plantuml)
    }
}
