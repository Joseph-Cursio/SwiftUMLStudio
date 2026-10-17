import Testing
@testable import SwiftUMLBridgeFramework

/// An "Unresolved:" note says that a call could not be followed. It belongs beside the participant
/// that made the call, which the edge names as `callerType` (#132). Each witness has a control, the
/// same source without the resolved call that comes before the unresolved one.
@Suite("An unresolved call's note sits beside its caller")
struct UnresolvedNoteAnchorTests {
    enum Witness: String, CaseIterable, Sendable {
        case depthOne, depthOneControl, depthTwo, depthTwoControl, nestedResolvedFirst

        /// The type whose method makes the call `handlers[0]()`.
        var caller: String {
            switch self {
            case .depthOne, .depthOneControl: "Screen"
            case .depthTwo, .depthTwoControl, .nestedResolvedFirst: "Store"
            }
        }

        var source: String {
            switch self {
            case .depthOne, .depthOneControl:
                // `Screen.start` calls `Store.shared.load()`, then its own `handlers[0]()`.
                """
                final class Store: Sendable {
                    static let shared = Store()
                    func load() {}
                }
                struct Screen {
                    var handlers: [() -> Void] = []
                    func start() {
                \(self == .depthOne ? "        Store.shared.load()" : "")
                        handlers[0]()
                    }
                }
                """
            case .depthTwo, .depthTwoControl, .nestedResolvedFirst:
                // `Screen.start` calls `Store.load()`, then `Cache.warm()`. `Store.load` calls
                // `handlers[0]()`, one level down, after `Logger.log()` in the last witness.
                """
                enum Store {
                    nonisolated(unsafe) static var handlers: [() -> Void] = []
                    static func load() {
                \(self == .nestedResolvedFirst ? "        Logger.log()" : "")
                        handlers[0]()
                    }
                }
                enum Cache {
                    static func warm() {}
                }
                enum Logger {
                    static func log() {}
                }
                struct Screen {
                    func start() {
                        Store.load()
                \(self == .depthTwoControl ? "" : "        Cache.warm()")
                    }
                }
                """
            }
        }
    }

    /// The edges `SequenceDiagramGenerator` hands the emitters for `Screen.start` at the default depth.
    private func script(_ witness: Witness, _ format: DiagramFormat) -> SequenceScript {
        let graph = CallGraph(edges: CallGraphExtractor.extract(from: witness.source).edges)
        return SequenceScript(
            traversedEdges: graph.traverse(from: "Screen", entryMethod: "start", maxDepth: 3),
            entryType: "Screen", entryMethod: "start", configuration: Configuration(format: format)
        )
    }

    private func noteLines(_ text: String) -> [String] {
        text.split(separator: "\n").map(String.init).filter { $0.lowercased().hasPrefix("note") }
    }

    @Test("Mermaid writes the note right of the caller", arguments: Witness.allCases)
    func mermaid(witness: Witness) {
        let notes = noteLines(script(witness, .mermaid).text)
        #expect(notes == ["Note right of \(witness.caller): Unresolved: handlers[0]()"])
    }

    /// `note right:` with no participant hangs on the message before it, which may be another
    /// method's; `note right of <caller>:` sits on the caller's lifeline, as Mermaid and SVG draw it.
    @Test("PlantUML writes the note right of the caller", arguments: Witness.allCases)
    func plantUML(witness: Witness) {
        let notes = noteLines(script(witness, .plantuml).text)
        #expect(notes == ["note right of \(witness.caller): Unresolved: handlers[0]()"])
    }

    /// The SVG layout starts the note at the anchor's lifeline (`fromX`) and centres it 60 to the right.
    @Test("the SVG layout anchors the note on the caller's lifeline", arguments: Witness.allCases)
    func svg(witness: Witness) throws {
        let layout = try #require(script(witness, .svg).sequenceLayout)
        let note = try #require(layout.messages.first { $0.isUnresolved })
        let anchor = layout.participants.first { $0.centerX == note.fromX }?.name
        #expect(anchor == witness.caller)
        #expect(note.toX == note.fromX + 60)
    }

    @Test("only the note lines move: the messages keep their text and order", arguments: Witness.allCases)
    func messagesUnchanged(witness: Witness) {
        let lines = script(witness, .mermaid).text.split(separator: "\n").map(String.init)
        let noteIndex = lines.firstIndex { $0.hasPrefix("Note") }
        let messages = lines.filter { $0.contains("->>") }
        switch witness {
        case .depthOne:
            #expect(messages == ["Screen->>Store.shared: load()"])
        case .depthOneControl:
            #expect(messages.isEmpty)
        case .depthTwo:
            #expect(messages == ["Screen->>Store: load()", "Screen->>Cache: warm()"])
        case .depthTwoControl:
            #expect(messages == ["Screen->>Store: load()"])
        case .nestedResolvedFirst:
            #expect(messages == ["Screen->>Store: load()", "Screen->>Cache: warm()", "Store->>Logger: log()"])
        }
        #expect(noteIndex == lines.count - 1)
    }

    // MARK: - Hand-built edges

    private func handBuilt(_ edges: [CallEdge], _ format: DiagramFormat) -> SequenceScript {
        SequenceScript(
            traversedEdges: edges, entryType: "Foo", entryMethod: "run", configuration: Configuration(format: format)
        )
    }

    /// The repo's own Mermaid and PlantUML fixture: `Foo.run` calls `Bar.process()`, `Bar.finish()`
    /// and then an unresolved `unknownClosure`, which is Foo's call.
    private let fixture = [
        CallEdge(callerType: "Foo", callerMethod: "run", calleeType: "Bar", calleeMethod: "process",
                 isAsync: false, isUnresolved: false),
        CallEdge(callerType: "Foo", callerMethod: "run", calleeType: "Bar", calleeMethod: "finish",
                 isAsync: true, isUnresolved: false),
        CallEdge(callerType: "Foo", callerMethod: "run", calleeType: nil, calleeMethod: "unknownClosure",
                 isAsync: false, isUnresolved: true)
    ]

    @Test("the emitter fixture's note sits beside Foo, which made the call")
    func fixtureNote() throws {
        #expect(noteLines(handBuilt(fixture, .mermaid).text) == ["Note right of Foo: Unresolved: unknownClosure()"])
        #expect(noteLines(handBuilt(fixture, .plantuml).text) == ["note right of Foo: Unresolved: unknownClosure()"])
        let layout = try #require(handBuilt(fixture, .svg).sequenceLayout)
        let note = try #require(layout.messages.first { $0.isUnresolved })
        #expect(layout.participants.first { $0.centerX == note.fromX }?.name == "Foo")
    }

    /// A caller that is not a participant can come only from hand-built edges. The note then goes
    /// beside the entry type, in every format, so no format names a participant it never declared.
    @Test("a note whose caller is no participant sits beside the entry type")
    func unknownCallerFallsBack() throws {
        let edges = [
            CallEdge(callerType: "Foo", callerMethod: "run", calleeType: "Bar", calleeMethod: "process",
                     isAsync: false, isUnresolved: false),
            CallEdge(callerType: "Ghost", callerMethod: "haunt", calleeType: nil, calleeMethod: "boo",
                     isAsync: false, isUnresolved: true)
        ]
        #expect(noteLines(handBuilt(edges, .mermaid).text) == ["Note right of Foo: Unresolved: boo()"])
        #expect(noteLines(handBuilt(edges, .plantuml).text) == ["note right of Foo: Unresolved: boo()"])
        let layout = try #require(handBuilt(edges, .svg).sequenceLayout)
        let note = try #require(layout.messages.first { $0.isUnresolved })
        #expect(layout.participants.first { $0.centerX == note.fromX }?.name == "Foo")
    }
}
