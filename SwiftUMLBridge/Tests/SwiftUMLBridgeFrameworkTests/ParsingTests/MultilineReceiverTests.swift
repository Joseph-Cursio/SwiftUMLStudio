import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// A call written across lines has the receiver it has on one line: `Store` / `.shared` / `.load()`
/// calls `load()` on `Store.shared`. The receiver was named by its text, line breaks and indent
/// included, so it was a participant apart from `Store.shared` and split each Mermaid and PlantUML
/// line naming it; `Unresolved:` notes and state guards did the same (#133). Each test reads a
/// source against the same source written on one line, the control.
@Suite("A receiver written across lines is the receiver written on one line")
struct MultilineReceiverTests {
    private static let split = """
        struct Screen {
            func start() {
                NotificationCenter
                    .default
                    .post(name: .init("x"), object: nil)
                Store.shared.load()
                Store
                    .shared
                    .save()
                Text("Hello")
                    .font(.title)
                    .padding()
            }
        }
        """

    private static let oneLine = """
        struct Screen {
            func start() {
                NotificationCenter.default.post(name: .init("x"), object: nil)
                Store.shared.load()
                Store.shared.save()
                Text("Hello").font(.title).padding()
            }
        }
        """

    private func callees(_ source: String) -> [String] {
        CallGraphExtractor.extract(from: source).edges.map { "\($0.calleeType ?? "unresolved") \($0.calleeMethod)" }
    }

    private func sequence(_ source: String, _ format: DiagramFormat) -> String {
        let edges = CallGraph(edges: CallGraphExtractor.extract(from: source).edges)
            .traverse(from: "Screen", entryMethod: "start", maxDepth: 3)
        return SequenceScript(traversedEdges: edges, entryType: "Screen", entryMethod: "start",
                              configuration: Configuration(format: format)).text
    }

    @Test("a receiver's line breaks are not part of it")
    func receiver() {
        let control = callees(Self.oneLine)
        #expect(control == ["NotificationCenter.default post", "Screen init", "Store.shared load",
                            "Store.shared save", "Text(\"Hello\").font(.title) padding", "Text font", "Screen Text"])
        #expect(callees(Self.split) == control)
    }

    @Test("a comment line inside a receiver is not part of it")
    func commentLineInReceiver() {
        let observed = callees("""
            struct Screen {
                func start() {
                    Store
                        // the shared one
                        .shared
                        .load()
                }
            }
            """)
        #expect(observed == ["Store.shared load"])
    }

    @Test("a comment within a line stays in the receiver")
    func commentWithinLine() {
        let observed = callees("""
            struct Screen {
                func start() {
                    Store /* the one */ .shared.load()
                }
            }
            """)
        #expect(observed == ["Store /* the one */ .shared load"])
    }

    @Test("the sequence diagram names each receiver once, on one line",
          arguments: [DiagramFormat.mermaid, .plantuml, .svg])
    func sequenceText(format: DiagramFormat) {
        #expect(sequence(Self.split, format) == sequence(Self.oneLine, format))
    }

    @Test("an unresolved call written across lines is noted on one line")
    func unresolvedCallee() {
        let observed = callees("""
            struct Screen {
                func start() {
                    let total = {
                        1 + 2
                    }()
                }
            }
            """)
        let control = callees("""
            struct Screen {
                func start() {
                    let total = { 1 + 2 }()
                }
            }
            """)
        #expect(control == ["unresolved { 1 + 2 }"])
        #expect(observed == control)
    }

    @Test("a state guard written across lines is labelled on one line")
    func stateGuard() {
        func guards(_ condition: String) -> [String] {
            StateMachineExtractor.extract(from: """
                enum Light { case red, green }
                final class Lamp {
                    var state: Light = .red
                    var armed = true
                    var ready = true
                    func next() {
                        switch state {
                        case .red where \(condition): state = .green
                        case .red: break
                        case .green: state = .red
                        }
                    }
                }
                """).flatMap(\.transitions).compactMap(\.guardText)
        }
        let control = guards("armed && ready")
        #expect(control == ["armed && ready"])
        #expect(guards("armed\n            && ready") == control)
    }
}
