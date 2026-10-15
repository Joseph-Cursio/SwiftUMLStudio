import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// `` `Plain` `` and `Plain` are one identifier, so sequence and activity diagrams file a method,
/// and the calls to it, under one name however each is spelt, and an entry point typed with
/// backticks is the one listed without them. Names were read as written: a call to
/// `` `Plain`.make() `` stayed unresolved, and `` func `helper`() `` called as `helper()` was not
/// followed (#123). A raw identifier or a keyword keeps its backticks everywhere, as before.
@Suite("Call graph and activity: names written with backticks")
struct CallGraphCanonicalNameTests {

    /// The issue's witness: the extension and one call escape the name the struct declares.
    static let plain = """
    struct Plain {
        func start() {
            helper()
            `Plain`.make()
        }
    }
    extension `Plain` {
        func helper() { deep() }
        func deep() {}
        static func make() {}
    }
    """

    /// The declaration escapes the name its extension and its calls do not.
    static let ticked = """
    struct `Ticked` {
        func start() {
            helper()
            Ticked.make()
        }
        static func make() {}
    }
    extension Ticked {
        func helper() { deep() }
        func deep() {}
    }
    """

    /// A method declared with backticks and called without them.
    static let tick = """
    struct Tick {
        func start() { helper() }
        func `helper`() { deep() }
        func deep() {}
    }
    """

    /// Names that need their backticks wherever they are written.
    static let needed = """
    struct `Foo Bar` {
        func start() { helper() }
    }
    extension `Foo Bar` {
        func helper() { deep() }
        func deep() {}
    }
    struct Keyed {
        func start() { `default`() }
        func `default`() { `class`() }
        func `class`() {}
    }
    """

    private static let formats: [DiagramFormat] = [.plantuml, .mermaid]

    /// `source` with every backtick removed: the same program, written without escapes.
    private func unescaped(_ source: String) -> String {
        source.replacingOccurrences(of: "`", with: "")
    }

    private func described(_ edges: [CallEdge]) -> [String] {
        edges.map { "\($0.callerType).\($0.callerMethod)->\($0.calleeType ?? "?").\($0.calleeMethod)" }
    }

    private func traversed(_ source: String, from type: String, _ method: String) -> [String] {
        let edges = CallGraphExtractor.extract(from: source).edges
        return described(CallGraph(edges: edges).traverse(from: type, entryMethod: method, maxDepth: 3))
    }

    /// `body`, given the path of a temporary file holding `source`.
    private func withSourceFile<Result>(_ source: String, _ body: (String) -> Result) throws -> Result {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return body(url.path)
    }

    /// The sequence diagram the CLI's `--entry type.method` draws for `source`.
    private func sequence(
        _ source: String, _ type: String, _ method: String, _ format: DiagramFormat
    ) throws -> String {
        try withSourceFile(source) { path in
            SequenceDiagramGenerator().generateScript(
                for: [path], entryType: type, entryMethod: method, with: Configuration(format: format)
            ).text
        }
    }

    /// The activity diagram the CLI's `--entry type.method` draws for `source`.
    private func activity(
        _ source: String, _ type: String, _ method: String, _ format: DiagramFormat
    ) throws -> String {
        try withSourceFile(source) { path in
            ActivityDiagramGenerator().generateScript(
                for: [path], entryType: type, entryMethod: method, with: Configuration(format: format)
            ).text
        }
    }

    // MARK: - The issue's witness

    @Test("the sequence diagram follows each call however the type is spelt", arguments: formats)
    func plainSequence(format: DiagramFormat) throws {
        let control = try sequence(unescaped(Self.plain), "Plain", "start", format)
        #expect(try sequence(Self.plain, "Plain", "start", format) == control)
        for call in ["helper()", "make()", "deep()"] {
            #expect(control.contains(call), "\(control)")
        }
    }

    @Test("the activity diagram finds a method of the escaped extension", arguments: formats)
    func plainActivity(format: DiagramFormat) throws {
        let control = try activity(unescaped(Self.plain), "Plain", "helper", format)
        #expect(try activity(Self.plain, "Plain", "helper", format) == control)
        #expect(control.contains("deep()"), "\(control)")
    }

    @Test("an entry point typed with backticks is the one listed without them", arguments: formats)
    func plainEscapedEntry(format: DiagramFormat) throws {
        let sequenceText = try sequence(Self.plain, "`Plain`", "helper", format)
        #expect(try sequenceText == sequence(Self.plain, "Plain", "helper", format))
        #expect(sequenceText.contains("deep()"), "\(sequenceText)")
        let activityText = try activity(Self.plain, "`Plain`", "helper", format)
        #expect(try activityText == activity(Self.plain, "Plain", "helper", format))
        #expect(activityText.contains("deep()"), "\(activityText)")
    }

    // MARK: - Declarations

    @Test("a type declared with backticks lists its methods, and is called, under its name")
    func escapedDeclaration() {
        #expect(CallGraphExtractor.extract(from: Self.ticked).methods
                == ["Ticked.deep", "Ticked.helper", "Ticked.make", "Ticked.start"])
        #expect(traversed(Self.ticked, from: "Ticked", "start") == [
            "Ticked.start->Ticked.helper", "Ticked.start->Ticked.make", "Ticked.helper->Ticked.deep"
        ])
    }

    @Test("a type declared with backticks draws the diagrams its plain spelling does", arguments: formats)
    func escapedDeclarationDiagrams(format: DiagramFormat) throws {
        let control = unescaped(Self.ticked)
        for type in ["Ticked", "`Ticked`"] {
            #expect(try sequence(Self.ticked, type, "start", format) == sequence(control, "Ticked", "start", format))
            #expect(try activity(Self.ticked, type, "start", format) == activity(control, "Ticked", "start", format))
        }
    }

    @Test("a method declared with backticks is followed from a call without them")
    func escapedMethod() throws {
        #expect(CallGraphExtractor.extract(from: Self.tick).methods == ["Tick.deep", "Tick.helper", "Tick.start"])
        #expect(traversed(Self.tick, from: "Tick", "start") == ["Tick.start->Tick.helper", "Tick.helper->Tick.deep"])
        let graph = ActivityFlowExtractor.extract(from: Self.tick, entryType: "Tick", entryMethod: "helper")
        #expect(try #require(graph).nodes.map(\.label).contains("deep()"))
        let typedIn = try activity(Self.tick, "Tick", "`helper`", .mermaid)
        #expect(try typedIn == activity(Self.tick, "Tick", "helper", .mermaid))
    }

    // MARK: - Calls

    @Test("a call on a type written with backticks goes where the call without them goes", arguments: [
        "`Plain`.make()", "`Plain`().build()", "`Outer`.Inner.make()", "Outer.`Inner`.make()"
    ])
    func escapedReceiver(call: String) {
        let declarations = """
        struct Plain { static func make() {}; func build() {} }
        struct Outer { struct Inner { static func make() {} } }
        """
        func edges(_ call: String) -> [String] {
            let source = "struct Caller { func run() { \(call) } }\n" + declarations
            return described(CallGraphExtractor.extract(from: source).edges)
        }
        let control = edges(unescaped(call))
        #expect(edges(call) == control)
        #expect(!control.contains { $0.contains("->?.") }, "\(control)")
    }

    @Test("a task group and its tasks are found when their names are written with backticks")
    func escapedTaskGroup() throws {
        let source = """
        struct Grouped {
            func run() async {
                await `withTaskGroup`(of: Void.self) { group in
                    group.`addTask` { work() }
                    group.addTask { rest() }
                }
            }
        }
        func work() {}
        func rest() {}
        """
        let graph = try #require(ActivityFlowExtractor.extract(from: source, entryType: "Grouped", entryMethod: "run"))
        let control = try #require(ActivityFlowExtractor.extract(
            from: unescaped(source), entryType: "Grouped", entryMethod: "run"
        ))
        #expect(graph.nodes == control.nodes)
        #expect(graph.edges == control.edges)
        #expect(control.nodes.filter { $0.kind == .fork }.count == 1)
        #expect(control.nodes.filter { $0.kind == .action }.map(\.label) == ["work()", "rest()"])
    }

    // MARK: - Controls

    @Test("a raw identifier and a keyword keep their backticks wherever they are written")
    func neededBackticks() {
        #expect(CallGraphExtractor.extract(from: Self.needed).methods == [
            "Keyed.`class`", "Keyed.`default`", "Keyed.start",
            "`Foo Bar`.deep", "`Foo Bar`.helper", "`Foo Bar`.start"
        ])
        #expect(traversed(Self.needed, from: "`Foo Bar`", "start") == [
            "`Foo Bar`.start->`Foo Bar`.helper", "`Foo Bar`.helper->`Foo Bar`.deep"
        ])
        #expect(traversed(Self.needed, from: "Keyed", "start") == [
            "Keyed.start->Keyed.`default`", "Keyed.`default`->Keyed.`class`"
        ])
    }

    @Test("a raw identifier or a keyword typed as the entry point is found", arguments: formats)
    func neededBackticksEntry(format: DiagramFormat) throws {
        #expect(try sequence(Self.needed, "`Foo Bar`", "start", format).contains("deep()"))
        #expect(try activity(Self.needed, "`Foo Bar`", "helper", format).contains("deep()"))
        #expect(try sequence(Self.needed, "Keyed", "start", format).contains("`class`()"))
        #expect(try activity(Self.needed, "Keyed", "`default`", format).contains("`class`()"))
    }

    @Test("the issue's witness written without backticks is drawn as before", arguments: formats)
    func unescapedControl(format: DiagramFormat) throws {
        let source = unescaped(Self.plain)
        let text = try sequence(source, "Plain", "start", format)
        for call in ["helper()", "make()", "deep()"] {
            #expect(text.contains(call), "\(text)")
        }
        #expect(try activity(source, "Plain", "helper", format).contains("deep()"))
    }
}
