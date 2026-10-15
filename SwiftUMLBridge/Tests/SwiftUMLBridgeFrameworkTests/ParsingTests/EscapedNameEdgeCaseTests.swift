import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// The places a name escaped on one side must still read as one name, beyond the issue's witnesses:
/// a typed-in exclude pattern, `` `self` `` as a receiver, attribute arguments, member names after a
/// `.`, GRDB class records and actor, enum and protocol entry types. And the one place backticks
/// must stay although the name is a valid variable name: a type member named `Type` or `Protocol`,
/// which Swift requires escaped, since after a `.` the bare word is a metatype (#123).
@Suite("Escaped names — edge cases")
struct EscapedNameEdgeCaseTests {

    /// `source` with every backtick removed: the same program, written without escapes.
    private func unescaped(_ source: String) -> String {
        source.replacingOccurrences(of: "`", with: "")
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

    private func sequence(_ source: String, _ type: String, _ method: String) throws -> String {
        try withSourceFile(source) { path in
            SequenceDiagramGenerator().generateScript(
                for: [path], entryType: type, entryMethod: method, with: Configuration(format: .mermaid)
            ).text
        }
    }

    private func activity(_ source: String, _ type: String, _ method: String) throws -> String {
        try withSourceFile(source) { path in
            ActivityDiagramGenerator().generateScript(
                for: [path], entryType: type, entryMethod: method, with: Configuration(format: .mermaid)
            ).text
        }
    }

    // MARK: - Names that keep their backticks

    @Test("a type member named Type or Protocol keeps the backticks Swift requires")
    func typeAndProtocolMembers() {
        let source = """
            struct Outer {
                struct `Type` {}
                var `Protocol`: Int = 0
                var meta: Outer.Type = Outer.self
                var nested: Outer.`Type` = .init()
            }
            """
        let text = ClassDiagramGenerator().generateScript(for: source, with: Configuration(format: .plantuml)).text
        #expect(text.contains("class \"`Type`\" as Outer.`Type`"), "\(text)")
        #expect(text.contains("~`Protocol` : Int"), "\(text)")
        #expect(text.contains("~meta : Outer.Type"), "\(text)")
        #expect(text.contains("~nested : Outer.`Type`"), "\(text)")
    }

    // MARK: - Typed-in patterns

    @Test("an exclude pattern written with backticks matches the name it escapes", arguments: ["`Base`", "Base"])
    func excludePattern(pattern: String) throws {
        let source = "class `Base` {}\nfinal class Sub: Base {}"
        let configuration = Configuration(elements: ElementOptions(exclude: [pattern]), format: .plantuml)
        let classes = ClassDiagramGenerator().generateScript(for: source, with: configuration).text
        #expect(!classes.contains("as Base "), "\(classes)")
        let deps = try withSourceFile(source) { path in
            DependencyGraphGenerator().generateScript(for: [path], mode: .types, with: configuration).text
        }
        #expect(!deps.contains("Base"), "\(deps)")
    }

    // MARK: - Receivers and member names

    @Test("`self` and `Self` are self and Self as receivers")
    func escapedSelf() throws {
        let source = """
            struct Caller {
                func run() { `self`.helper(); `Self`.make() }
                func helper() { deep() }
                func deep() {}
                static func make() {}
            }
            """
        let control = try sequence(unescaped(source), "Caller", "run")
        #expect(control.contains("Caller->>Caller: deep()"), "\(control)")
        #expect(try sequence(source, "Caller", "run") == control)
    }

    @Test("a state machine switched over `self`.property is found as over self.property")
    func escapedSelfStateMachine() {
        let source = """
            enum Light { case off, on }
            final class Lamp {
                var light: Light = .off
                func toggle() {
                    switch `self`.light {
                    case .off: self.light = .on
                    case .on: self.light = .off
                    }
                }
            }
            """
        let control = StateMachineExtractor.extract(from: unescaped(source))
        #expect(control.first?.confidence == .high)
        #expect(StateMachineExtractor.extract(from: source) == control)
    }

    @Test("a task group named with backticks is labelled as the one without them")
    func escapedTaskGroupLabel() throws {
        let source = """
            struct Grouped {
                func run() async {
                    await `withTaskGroup`(of: Void.self) { group in print("no tasks") }
                }
            }
            """
        let graph = try #require(ActivityFlowExtractor.extract(from: source, entryType: "Grouped", entryMethod: "run"))
        let control = try #require(ActivityFlowExtractor.extract(
            from: unescaped(source), entryType: "Grouped", entryMethod: "run"
        ))
        #expect(control.nodes.contains { $0.label == "withTaskGroup { … }" }, "\(control.nodes.map(\.label))")
        #expect(graph.nodes == control.nodes)
    }

    // MARK: - Attribute arguments and records

    @Test("an ER attribute's arguments read as Swift reads them")
    func erAttributeArguments() {
        let source = """
            import SwiftData
            @Model final class Account {
                @Attribute(.`unique`) var code: String = ""
                @Relationship(deleteRule: .cascade, `inverse`: \\Item.owner) var items: [Item] = []
                init() {}
            }
            @Model final class Item {
                var owner: Account?
                init() {}
            }
            """
        let model = ERModelExtractor.extract(from: source)
        let control = ERModelExtractor.extract(from: unescaped(source))
        #expect(control.entities.flatMap(\.attributes).contains { $0.name == "code" && $0.isUnique })
        #expect(control.relationships.count == 1)
        #expect(model == control)
    }
}
