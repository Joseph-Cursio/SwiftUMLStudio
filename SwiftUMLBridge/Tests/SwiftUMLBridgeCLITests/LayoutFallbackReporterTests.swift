import Foundation
import Synchronization
import Testing
import SwiftUMLBridgeFramework
@testable import swiftumlbridge

/// A script holding `layoutGraph`, as a class diagram or deps graph in SVG does.
private struct StubScript: DiagramOutputting {
    let text = "<svg/>"
    let format = DiagramFormat.svg
    let layoutGraph: LayoutGraph?
}

/// Records what it is given, in order: `presented` for a script, the text for a report.
private final class Recorder: DiagramPresenting {
    let events = Mutex<[String]>([])

    func present(script: any DiagramOutputting) async {
        events.withLock { $0.append("presented") }
    }

    func record(_ text: String) {
        events.withLock { $0.append(text) }
    }
}

/// A graph the layout engine put on its grid, because of `reason`.
private func fallenBack(_ reason: String) -> LayoutGraph {
    var graph = LayoutGraph(nodes: [LayoutNode(id: "A", label: "A")])
    graph.fallbackReason = reason
    return graph
}

/// When the SVG layout falls back to its grid, the diagram is still written and the exit status
/// is unchanged, so a line on stderr is the only sign (#150).
@Suite("LayoutFallbackReporter")
struct LayoutFallbackReporterTests {

    @Test("a fallback gets one warning line naming the reason")
    func warningText() {
        let script = StubScript(layoutGraph: fallenBack("RangeError: Maximum call stack size exceeded."))
        #expect(LayoutFallbackReporter.warning(for: script) == """
            warning: the SVG layout failed (RangeError: Maximum call stack size exceeded.), \
            so the boxes are on a grid

            """)
    }

    @Test("a layout dagre made, or no layout at all, gets no warning")
    func noWarning() {
        #expect(LayoutFallbackReporter.warning(for: StubScript(layoutGraph: LayoutGraph())) == nil)
        #expect(LayoutFallbackReporter.warning(for: StubScript(layoutGraph: nil)) == nil)
    }

    @Test("the diagram is presented first, then the warning reported")
    func presentsThenReports() async {
        let recorder = Recorder()
        let reporter = LayoutFallbackReporter(inner: recorder) { recorder.record($0) }
        await reporter.present(script: StubScript(layoutGraph: fallenBack("a test")))
        await reporter.present(script: StubScript(layoutGraph: LayoutGraph()))
        let events = recorder.events.withLock { $0 }
        #expect(events.count == 3)
        #expect(events.first == "presented")
        #expect(events.dropFirst().first?.hasPrefix("warning: the SVG layout failed (a test)") == true)
        #expect(events.last == "presented")
    }

    /// By raw value, since `ClassDiagramOutput` is not `Sendable`; `nil` is no `--output`.
    @Test("every --output wraps its presenter in the reporter", arguments: [
        nil, "browser", "browserImageOnly", "consoleOnly"
    ] as [String?])
    func routing(rawValue: String?) throws {
        let output = try rawValue.map { try #require(ClassDiagramOutput(rawValue: $0)) }
        let reporter = output.reportingPresenter as? LayoutFallbackReporter
        #expect(reporter.map { type(of: $0.inner) == type(of: output.presenter) } == true)
    }

    /// A graph dagre lays out writes nothing but the diagram.
    @Test("an SVG class diagram dagre lays out prints no warning")
    func cliWritesNoWarning() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swiftumlbridge-cli-fallback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "class Base {}\nclass Leaf: Base {}\n"
            .write(to: root.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)

        let run = try runCLI(["classdiagram", "App.swift", "--format", "svg", "--output", "consoleOnly"], in: root)
        #expect(run.status == 0)
        #expect(run.output.hasPrefix("<svg"))
        #expect(!run.output.contains("warning:"))
    }
}
