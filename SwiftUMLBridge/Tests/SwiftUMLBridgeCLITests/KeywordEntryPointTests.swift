import Foundation
import Testing

/// `--entry Keyed.default` names `` func `default`() ``, as a call written `self.default()` does:
/// after a `.`, Swift needs no backticks on a keyword (#130). It found nothing before.
@Suite("Keyword entry points typed without backticks")
struct KeywordEntryPointTests {
    private static let source = """
        struct Keyed {
            func `default`() { helper() }
            static func `import`() { load() }
            func helper() {}
            static func load() {}
        }
        """

    private func withSourceDirectory<Result>(_ body: (URL) throws -> Result) throws -> Result {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swiftumlbridge-keyword-entry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.source.write(to: directory.appendingPathComponent("Keyed.swift"), atomically: true, encoding: .utf8)
        return try body(directory)
    }

    @Test("sequence and activity draw the same diagram for either spelling", arguments: [
        ("sequence", "default", "helper()"), ("sequence", "import", "load()"),
        ("activity", "default", "helper()"), ("activity", "import", "load()")
    ])
    func eitherSpelling(command: String, method: String, callee: String) throws {
        try withSourceDirectory { directory in
            func run(_ entry: String) throws -> String {
                let result = try runCLI(
                    [command, ".", "--entry", entry, "--format", "mermaid", "--output", "consoleOnly"], in: directory
                )
                #expect(result.status == 0)
                return result.output
            }
            let bare = try run("Keyed.\(method)")
            #expect(bare.contains(callee))
            #expect(bare == (try run("Keyed.`\(method)`")))
        }
    }
}
