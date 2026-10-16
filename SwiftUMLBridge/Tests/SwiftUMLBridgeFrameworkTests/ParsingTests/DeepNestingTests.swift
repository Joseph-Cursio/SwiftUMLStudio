import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// Each parse recursed once per level of nesting, on whatever thread called it. Swift Testing
/// runs a test on a cooperative thread with a 512 KB stack, as the CLI runs its commands and
/// Studio its detached tasks, so 18 nested calls overflowed it in a debug build, and took the
/// whole test process down with it (#71). Every entry point that parses goes through
/// `ParsingStack.run` now.
///
/// Each source also has something after the nested calls. A debug build's SwiftParser stopped 20
/// levels in by default and read the rest of the file as unexpected tokens, so it lost
/// everything after them. It now goes as deep as a release build, `ParsingStack.maximumNestingLevel`.
@Suite("A deeply nested expression no longer overflows the stack or hides what follows it")
struct DeepNestingTests {

    /// `f(f(…f(0)…))`, `depth` calls deep. 100 is past both depths that crashed, 18 in a debug
    /// build and 55 in a release one.
    static func nestedCalls(_ depth: Int = 100) -> String {
        String(repeating: "f(", count: depth) + "0" + String(repeating: ")", count: depth)
    }

    private func temporaryFile(_ source: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("deep-nesting-\(UUID().uuidString).swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test("these tests run on a stack too small for the parse")
    func smallStack() {
        #expect(Thread.current.stackSize < ParsingStack.size)
    }

    @Test("a class diagram is drawn")
    func classDiagram() {
        let text = ClassDiagramGenerator().generateScript(
            for: "struct Before {}\nstruct S {\n    let x = \(Self.nestedCalls())\n}\nstruct After {}\n",
            with: Configuration(format: .plantuml)
        ).text
        #expect(text.contains("as Before "), "\(text)")
        #expect(text.contains("as S "), "\(text)")
        #expect(text.contains("as After "), "\(text)")
    }

    @Test("a dependency graph is drawn from a file")
    func dependencyGraph() throws {
        let file = try temporaryFile("class Before: Base {}\nlet x = \(Self.nestedCalls())\nclass After: Base {}\n")
        defer { try? FileManager.default.removeItem(at: file) }
        let text = DependencyGraphGenerator()
            .generateScript(for: [file.path], mode: .types, with: Configuration(format: .plantuml)).text
        #expect(text.contains("Before --> Base"), "\(text)")
        #expect(text.contains("After --> Base"), "\(text)")
    }

    @Test("a state machine is found")
    func stateMachine() {
        let machines = StateMachineExtractor.extract(from: """
            enum Light { case red, green }
            final class Lamp {
                var state: Light = .red
                func next() {
                    switch state {
                    case .red: state = .green
                    case .green: state = .red
                    }
                }
            }
            let x = \(Self.nestedCalls())
            enum Door { case open, shut }
            final class Gate {
                var state: Door = .open
                func toggle() {
                    switch state {
                    case .open: state = .shut
                    case .shut: state = .open
                    }
                }
            }
            """)
        #expect(machines.map(\.identifier).sorted() == ["Gate.Door", "Lamp.Light"])
    }

    @Test("a SwiftData model is found")
    func swiftDataModel() {
        let model = ERModelExtractor.extract(from: """
            @Model final class Owner { var name: String = "" }
            let x = \(Self.nestedCalls())
            @Model final class Pet { var tag: String = "" }
            """)
        #expect(model.entities.map(\.name) == ["Owner", "Pet"])
    }

    @Test("a GRDB record is found")
    func grdbRecord() {
        let model = PersistenceSchemaExtractor.extract(from: """
            struct Player: FetchableRecord { var id: Int64 }
            let x = \(Self.nestedCalls())
            struct Team: FetchableRecord { var id: Int64 }
            """)
        #expect(model.entities.map(\.name) == ["Player", "Team"])
    }

    @Test("a call is found")
    func callGraph() {
        let result = CallGraphExtractor.extract(from: """
            struct S {
                func start() { load() }
                func deep() { _ = \(Self.nestedCalls()) }
                func finish() { save() }
            }
            """)
        #expect(result.edges.contains { $0.callerMethod == "start" && $0.calleeMethod == "load" })
        #expect(result.edges.contains { $0.callerMethod == "finish" && $0.calleeMethod == "save" })
    }

    @Test("an activity graph is built")
    func activityGraph() throws {
        let source = """
            struct S {
                func run() {
                    load()
                    _ = \(Self.nestedCalls())
                    save()
                }
            }
            """
        let graph = try #require(ActivityFlowExtractor.extract(from: source, entryType: "S", entryMethod: "run"))
        #expect(graph.nodes.map(\.label).contains("load()"))
        #expect(graph.nodes.map(\.label).contains("save()"))
    }

    @Test("an import is found")
    func importEdge() {
        let edges = ImportExtractor.extract(
            from: "import Foundation\nlet x = \(Self.nestedCalls())\nimport Combine\n", sourceModule: "App"
        )
        #expect(edges.map(\.importedModule) == ["Foundation", "Combine"])
    }

    /// Past the cap SwiftParser still reads the rest of the file as unexpected tokens, in every
    /// build, but on this stack it gets there without overflowing.
    @Test("past the nesting cap the parse still ends, and keeps what came before")
    func pastTheCap() {
        let depth = ParsingStack.maximumNestingLevel * 4
        let text = ClassDiagramGenerator().generateScript(
            for: "struct Before {}\nstruct S {\n    let x = \(Self.nestedCalls(depth))\n}\n",
            with: Configuration(format: .plantuml)
        ).text
        #expect(text.contains("as Before "), "\(text)")
    }
}

@Suite("ParsingStack")
struct ParsingStackTests {

    @Test("runs its body on a thread with the large stack")
    func runsOnTheLargeStack() {
        #expect(ParsingStack.run { Thread.current.stackSize } >= ParsingStack.size)
    }

    @Test("stays on its thread when it is already on a large stack")
    func nestedRunStaysOnItsThread() {
        let sameThread = ParsingStack.run {
            let outer = ObjectIdentifier(Thread.current)
            return ParsingStack.run { ObjectIdentifier(Thread.current) } == outer
        }
        #expect(sameThread)
    }
}
