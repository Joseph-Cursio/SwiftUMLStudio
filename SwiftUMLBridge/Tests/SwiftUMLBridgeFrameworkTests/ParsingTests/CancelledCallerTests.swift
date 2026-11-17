import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

/// Studio cancels a generation that a newer one replaces, and drops its result. A cancelled
/// caller's parses read nothing and its class diagram draws nothing, so the replaced run ends
/// soon after the cancel instead of running to its end (#236). Each test runs the work in a task
/// that cancels itself first, so the work always sees the cancel.
@Suite("A cancelled caller parses and draws nothing")
struct CancelledCallerTests {

    /// `work`'s result in a task cancelled before `work` starts, and in one never cancelled.
    private static func cancelledAndNot<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> (T, T) {
        let cancelled = await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return work()
        }.value
        let uncancelled = await Task.detached { work() }.value
        return (cancelled, uncancelled)
    }

    private static let source = """
        import SwiftData
        @Model final class Order { var total: Int = 0 }
        class Store {}
        final class Shop: Store {
            let label: String = "x"
            func buy() { Order().total += 1 }
        }
        """

    /// A directory holding `source`, for the generators that read paths.
    private static func directory() throws -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cancelled-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try source.write(to: directory.appendingPathComponent("Shop.swift"), atomically: true, encoding: .utf8)
        return directory.path
    }

    /// On the task's own thread `Task.isCancelled` says so; on the thread `ParsingStack.run`
    /// starts, which has no task, the flag `run` passes on does.
    @Test("a parse reads nothing, on the task's thread and on a parsing thread")
    func parseReadsNothing() async {
        let (onTask, notOnTask) = await Self.cancelledAndNot { ParsingStack.parse(Self.source).statements.count }
        #expect(onTask == 0)
        #expect(notOnTask > 0)
        let (onThread, notOnThread) = await Self.cancelledAndNot {
            ParsingStack.run { ParsingStack.parse(Self.source).statements.count }
        }
        #expect(onThread == 0)
        #expect(notOnThread > 0)
    }

    @Test("the SourceKit typename supplement reads nothing")
    func supplementReadsNothing() async {
        let (cancelled, uncancelled) = await Self.cancelledAndNot {
            ParsingStack.run { SyntaxStructure.buildTypenameMap(from: "struct S { var a, b: Int }", sdkPath: nil) }
        }
        #expect(cancelled.isEmpty)
        #expect(!uncancelled.isEmpty)
    }

    /// Every generator parses through `ParsingStack.parse`, so none finds a type: `Shop`, or
    /// `Order` for an ER diagram, which draws SwiftData models alone, and for a sequence diagram,
    /// which names its entry's type whatever it finds.
    @Test("no generator finds a type", arguments: ["class", "class-svg", "deps", "sequence", "er"])
    func generatorsFindNothing(kind: String) async throws {
        let path = try Self.directory()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let (cancelled, uncancelled) = await Self.cancelledAndNot { () -> String in
            switch kind {
            case "class-svg":
                return ClassDiagramGenerator().generateScript(for: [path], with: Configuration(format: .svg)).text

            case "deps":
                return DependencyGraphGenerator().generateScript(for: [path], mode: .types, with: .default).text

            case "sequence":
                return SequenceDiagramGenerator().generateScript(
                    for: [path], entryType: "Shop", entryMethod: "buy", depth: 3, with: .default
                ).text

            case "er":
                return ERDiagramGenerator().generateScript(for: [path], with: .default).text

            default:
                return ClassDiagramGenerator().generateScript(for: [path], with: Configuration(format: .plantuml)).text
            }
        }
        let name = kind == "er" || kind == "sequence" ? "Order" : "Shop"
        #expect(uncancelled.contains(name), "\(uncancelled)")
        #expect(!cancelled.contains(name), "\(cancelled)")
    }

    /// Items parsed before the cancel are not drawn: in the text formats, and in SVG's layout.
    @Test("items parsed before the cancel are not drawn", arguments: [DiagramFormat.plantuml, .mermaid, .svg])
    func drawingStops(format: DiagramFormat) async throws {
        let parsed = try #require(SyntaxStructure.create(from: Self.source)?.substructure)
        let (cancelled, uncancelled) = await Self.cancelledAndNot {
            DiagramScript(items: parsed, configuration: Configuration(format: format)).text
        }
        #expect(uncancelled.contains("Shop"), "\(uncancelled)")
        #expect(!cancelled.contains("Shop"), "\(cancelled)")
        let (nodes, allNodes) = await Self.cancelledAndNot {
            LayoutGraphBuilder.buildClassDiagram(from: parsed, configuration: Configuration(format: .svg)).nodes.count
        }
        #expect(nodes == 0)
        #expect(allNodes > 0)
    }
}
