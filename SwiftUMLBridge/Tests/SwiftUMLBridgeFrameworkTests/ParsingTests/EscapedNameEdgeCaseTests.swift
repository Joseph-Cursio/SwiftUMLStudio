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
}
