import Foundation
import SwiftParser
import SwiftSyntax
import Testing
@testable import SwiftUMLBridgeFramework

/// A keyword used as a member name must be escaped where it is declared (`` func `default`() ``),
/// but not after a `.`: `self.default()`, `.default` and `\Book.default` name the same member. The
/// parsers kept the declaration's backticks and read the reference bare, so the two never matched
/// (#130). Each witness here is checked against its control, the same source with the reference
/// escaped as the declaration is, which worked before.
@Suite("Keyword members referenced after a dot")
struct KeywordMemberAfterDotTests {
    static let calls = """
        struct Keyed {
            func start() {
                self.default()
                Keyed.import()
            }
            func `default`() { helper() }
            static func `import`() { load() }
            func helper() {}
            static func load() {}
        }
        """

    static let light = """
        enum Light { case `default`, off }
        final class Lamp {
            var state: Light = .default
            func toggle() {
                switch state {
                case .default: state = .off
                case .off: state = .default
                }
            }
        }
        """

    static let lampProperty = """
        enum Light { case off, on }
        final class Lamp {
            var `default`: Light = .off
            func toggle() {
                switch self.default {
                case .off: self.default = .on
                case .on: self.default = .off
                }
            }
        }
        """

    static let books = """
        import SwiftData

        @Model final class Author {
            @Relationship(inverse: \\Book.default)
            var books: [Book] = []
            init() {}
        }

        @Model final class Book {
            var `default`: Author?
            init() {}
        }
        """

    static let formats: [DiagramFormat] = [.plantuml, .mermaid]

    /// `source` with each reference after a dot escaped as its declaration is.
    private func escaped(_ source: String) -> String {
        source.replacingOccurrences(of: ".default", with: ".`default`")
            .replacingOccurrences(of: ".import", with: ".`import`")
    }

    private func withSourceFile<Result>(_ source: String, _ body: (String) -> Result) throws -> Result {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyword-\(UUID().uuidString).swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return body(url.path)
    }

    private func sequence(
        _ source: String, _ type: String, _ method: String, format: DiagramFormat = .mermaid
    ) throws -> String {
        try withSourceFile(source) { path in
            SequenceDiagramGenerator().generateScript(
                for: [path], entryType: type, entryMethod: method, with: Configuration(format: format)
            ).text
        }
    }

    private func activity(
        _ source: String, _ type: String, _ method: String, format: DiagramFormat = .mermaid
    ) throws -> String {
        try withSourceFile(source) { path in
            ActivityDiagramGenerator().generateScript(
                for: [path], entryType: type, entryMethod: method, with: Configuration(format: format)
            ).text
        }
    }

    private func state(_ source: String, format: DiagramFormat) throws -> String {
        try withSourceFile(source) { path in
            StateMachineGenerator().generateScript(
                for: [path], stateIdentifier: "Lamp.Light", with: Configuration(format: format)
            ).text
        }
    }

    private func entityRelationship(_ source: String, format: DiagramFormat) throws -> String {
        try withSourceFile(source) { path in
            ERDiagramGenerator().generateScript(for: [path], with: Configuration(format: format)).text
        }
    }

    // MARK: - Sequence and activity

    @Test("the sequence diagram follows self.default() and Keyed.import() into their bodies")
    func sequenceFollowsKeywordCalls() throws {
        let text = try sequence(Self.calls, "Keyed", "start")
        #expect(text.contains("Keyed->>Keyed: helper()"))
        #expect(text.contains("Keyed->>Keyed: load()"))
        #expect(!text.contains("Unresolved"))
    }

    /// A label is the call as written, so only the two labels differ from the control's.
    @Test("a keyword call written bare draws what its escaped control draws", arguments: formats)
    func sequenceMatchesControl(format: DiagramFormat) throws {
        let witness = try sequence(Self.calls, "Keyed", "start", format: format)
        let control = try sequence(escaped(Self.calls), "Keyed", "start", format: format)
        #expect(witness.contains("default()") && witness.contains("import()") && !witness.contains("`"))
        #expect(witness == control.replacingOccurrences(of: "`", with: ""))
    }

    @Test("a call written either way is followed into the method's body once")
    func bothSpellingsVisitOnce() throws {
        let source = """
            struct Keyed {
                func start() {
                    self.default()
                    self.`default`()
                }
                func `default`() { helper() }
                func helper() {}
            }
            """
        let lines = try sequence(source, "Keyed", "start").split(separator: "\n")
        #expect(lines.filter { $0.hasSuffix(": helper()") }.count == 1)
        #expect(lines.contains("Keyed->>Keyed: default()") && lines.contains("Keyed->>Keyed: `default`()"))
    }

    @Test("a call to a keyword member the sources do not declare keeps its label")
    func undeclaredKeywordMemberLabel() throws {
        let source = """
            struct Reader {
                func read(node: Node) {
                    _ = node.as(Int.self)
                    _ = Reader.default()
                }
            }
            """
        let text = try sequence(source, "Reader", "read")
        #expect(text.contains("Note right of Reader: Unresolved: as()"))
        #expect(text.contains("Reader->>Reader: default()"))
    }

    @Test("an entry typed without backticks finds the escaped method", arguments: formats)
    func entryWithoutBackticks(format: DiagramFormat) throws {
        for method in ["default", "import"] {
            let sequenceText = try sequence(Self.calls, "Keyed", method, format: format)
            let activityText = try activity(Self.calls, "Keyed", method, format: format)
            #expect(sequenceText == (try sequence(Self.calls, "Keyed", "`\(method)`", format: format)))
            #expect(activityText == (try activity(Self.calls, "Keyed", "`\(method)`", format: format)))
        }
        #expect(try sequence(Self.calls, "Keyed", "default", format: format).contains("helper()"))
        #expect(try activity(Self.calls, "Keyed", "default", format: format).contains("helper()"))
        #expect(try sequence(Self.calls, "Keyed", "import", format: format).contains("load()"))
    }

    @Test("entry points still list a keyword method as it is declared")
    func entryPointsListDeclaredSpelling() throws {
        let entries = try withSourceFile(Self.calls) { CallGraphExtractor.entryPoints(for: [$0]) }
        #expect(entries == ["Keyed.`default`", "Keyed.`import`", "Keyed.helper", "Keyed.load", "Keyed.start"])
    }

    @Test("x.init() is an initializer call, not func `init`()")
    func initIsNotAMember() {
        let source = """
            struct Maker {
                func start() { _ = Maker.init() }
                func `init`() { helper() }
                func helper() {}
            }
            """
        let result = CallGraphExtractor.extract(from: source)
        #expect(result.methods.contains("Maker.`init`"))
        let graph = CallGraph(edges: result.edges)
        let traversed = graph.traverse(from: "Maker", entryMethod: "start", maxDepth: 5)
        #expect(traversed.map(\.calleeMethod) == ["init"])
    }

    // MARK: - State

    @Test("every transition of a state machine ends at one of the enum's cases")
    func stateTransitionsUseDeclaredCases() throws {
        let model = try #require(StateMachineExtractor.extract(from: Self.light).first)
        let ends = Set(model.transitions.flatMap { [$0.from, $0.toState] })
        #expect(ends.isSubset(of: model.states.map(\.name)))
        #expect(model.states.map(\.name) == ["`default`", "off"])
    }

    @Test("a case assigned and matched bare draws what its escaped control draws", arguments: formats)
    func stateMatchesControl(format: DiagramFormat) throws {
        let witness = try state(Self.light, format: format)
        #expect(witness == (try state(escaped(Self.light), format: format)))
        #expect(witness.contains("`default` --> off : toggle()"))
    }

    @Test("a state property named with a keyword and assigned through self. is a state machine")
    func keywordStateProperty() {
        let identifiers = StateMachineExtractor.extract(from: Self.lampProperty).map(\.identifier)
        #expect(identifiers == ["Lamp.Light"])
    }

    @Test("a keyword state property draws what its escaped control draws", arguments: formats)
    func statePropertyMatchesControl(format: DiagramFormat) throws {
        let witness = try state(Self.lampProperty, format: format)
        #expect(witness == (try state(escaped(Self.lampProperty), format: format)))
        #expect(witness.contains("off --> on : toggle()"))
    }

    // MARK: - ER

    @Test("an inverse written \\Book.default is the relationship var `default` declares")
    func inverseWithoutBackticks() throws {
        let relationships = ERModelExtractor.extract(from: Self.books).relationships
        #expect(relationships.count == 1)
        let relationship = try #require(relationships.first)
        #expect(relationship.from == "Author" && relationship.label == "books")
        #expect(relationship.inverseLabel == "`default`")
    }

    @Test("an inverse written bare draws what its escaped control draws", arguments: formats)
    func entityRelationshipMatchesControl(format: DiagramFormat) throws {
        let witness = try entityRelationship(Self.books, format: format)
        #expect(witness == (try entityRelationship(escaped(Self.books), format: format)))
    }

    // MARK: - Controls

    @Test("controls with the backticks written after the dot")
    func controls() throws {
        let sequenceText = try sequence(escaped(Self.calls), "Keyed", "start")
        #expect(sequenceText.contains("helper()") && sequenceText.contains("load()"))
        #expect(try activity(Self.calls, "Keyed", "`default`").contains("helper()"))
        let model = try #require(StateMachineExtractor.extract(from: escaped(Self.light)).first)
        #expect(Set(model.transitions.flatMap { [$0.from, $0.toState] }).isSubset(of: model.states.map(\.name)))
        #expect(StateMachineExtractor.extract(from: escaped(Self.lampProperty)).map(\.identifier) == ["Lamp.Light"])
        #expect(ERModelExtractor.extract(from: escaped(Self.books)).relationships.count == 1)
    }
}

/// A member named after a `.` is read as its declaration is: a keyword written bare there gets
/// the backticks its declaration needs, and every other name reads as `canonicalName` (#130).
@Suite("Member names read after a dot")
struct MemberReferenceNameTests {
    static let spellings: [(String, String)] = [
        ("default", "`default`"), ("`default`", "`default`"), ("import", "`import`"), ("class", "`class`"),
        ("helper", "helper"), ("`helper`", "helper"), ("open", "open"), ("async", "async"),
        ("init", "init"), ("self", "self"), ("Type", "Type"), ("`Type`", "`Type`"), ("`go now`", "`go now`")
    ]

    @Test("the name after x. reads as its declaration does", arguments: spellings)
    func memberReferenceName(spelling: String, expected: String) throws {
        let file = Parser.parse(source: "x.\(spelling)")
        let item = try #require(file.statements.first?.item.as(ExprSyntax.self))
        let member = try #require(item.as(MemberAccessExprSyntax.self))
        #expect(member.declName.baseName.memberReferenceName == expected)
    }

    @Test("a member name typed in reads as one written after a dot", arguments: spellings + [
        ("", ""), ("go now", "go now")
    ])
    func canonicalMemberIdentifier(spelling: String, expected: String) {
        #expect(spelling.canonicalMemberIdentifier == expected)
    }

    @Test("listedEntryPoint escapes a keyword method typed bare")
    func listedEntryPoint() {
        let listed = CallGraphExtractor.listedEntryPoint(type: "`Keyed`", method: "default")
        #expect(listed.type == "Keyed" && listed.method == "`default`")
    }

    @Test("traverse follows a bare keyword callee, and an entry typed bare, into the escaped method")
    func traverseNormalisesMethod() {
        let edges = [
            CallEdge(callerType: "Keyed", callerMethod: "start", calleeType: "Keyed", calleeMethod: "default",
                     isAsync: false, isUnresolved: false),
            CallEdge(callerType: "Keyed", callerMethod: "`default`", calleeType: "Keyed", calleeMethod: "helper",
                     isAsync: false, isUnresolved: false)
        ]
        let graph = CallGraph(edges: edges)
        #expect(graph.traverse(from: "Keyed", entryMethod: "start", maxDepth: 3).map(\.calleeMethod)
            == ["default", "helper"])
        #expect(graph.traverse(from: "Keyed", entryMethod: "default", maxDepth: 3).map(\.calleeMethod) == ["helper"])
    }
}
