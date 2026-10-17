import Foundation
import Testing
@testable import swiftumlbridge

/// A chain of `[` nested past the parsers' limit is read with its deepest brackets as spaces, so
/// the parse ends; the CLI says so on stderr, naming the file, whatever the subcommand (#148).
/// Before, a 26-deep chain took 14 s and a 248-deep one never finished, with nothing printed.
@Suite("Chains of nested [ in the CLI")
struct NestedSquareBracketCLITests {
    private static let source = "struct S {\n    let x = " + String(repeating: "[", count: 248) + "1"
        + String(repeating: "]", count: 248) + "\n    let height = 2\n}\nstruct After {}\n"

    private func withSourceDirectory<Result>(_ body: (URL, URL) throws -> Result) throws -> Result {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swiftumlbridge-nested-brackets-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Deep.swift")
        try Self.source.write(to: file, atomically: true, encoding: .utf8)
        return try body(directory, file)
    }

    @Test("each subcommand reads the file and warns once, naming it", arguments: [
        ["classdiagram", ".", "--format", "plantuml"], ["deps", ".", "--types"], ["deps", ".", "--modules"],
        ["sequence", ".", "--entry", "S.x"], ["activity", ".", "--entry", "S.x"], ["state", ".", "--list"]
    ])
    func warns(arguments: [String]) throws {
        try withSourceDirectory { directory, file in
            let result = try runCLI(arguments + ["--output", "consoleOnly"], in: directory)
            #expect(result.status == 0)
            let warnings = result.output.split(separator: "\n").filter { $0.hasPrefix("warning: ") }
            #expect(warnings.count == 1)
            #expect(warnings.first?.contains("\(file.lastPathComponent):2:") == true)
            if arguments[0] == "classdiagram" {
                #expect(result.output.contains("as After ") && result.output.contains("~height"))
            }
        }
    }

    @Test("a subcommand that fails still warns, before its error")
    func warnsOnFailure() throws {
        try withSourceDirectory { directory, _ in
            let result = try runCLI(["er", ".", "--output", "consoleOnly"], in: directory)
            #expect(result.status == 1)
            let lines = result.output.split(separator: "\n")
            let warning = try #require(lines.firstIndex { $0.hasPrefix("warning: ") && $0.contains("Deep.swift:2:") })
            let error = try #require(lines.firstIndex { $0.hasPrefix("Error: No persisted models") })
            #expect(warning < error)
        }
    }

    @Test("the reporter writes one warning line a notice, and nothing for none")
    func reporterLines() {
        #expect(SourceReadNoticeReporter.warnings(for: ["a.swift:2:3: a", "b.swift:4:5: b"])
            == "warning: a.swift:2:3: a\nwarning: b.swift:4:5: b\n")
        #expect(SourceReadNoticeReporter.warnings(for: []).isEmpty)
    }
}
