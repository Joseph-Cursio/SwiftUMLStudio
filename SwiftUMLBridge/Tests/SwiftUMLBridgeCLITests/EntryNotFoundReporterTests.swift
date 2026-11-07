import Foundation
import Testing
@testable import swiftumlbridge

/// `sequence` and `activity` say on stderr when `--entry` came to no method with a body, where
/// they drew an empty diagram with no word of why (#239).
@Suite("EntryNotFoundReporter")
struct EntryNotFoundReporterTests {
    @Test("an entry that was not found gets a warning naming it as typed")
    func warnsWhenNotFound() {
        #expect(EntryNotFoundReporter.warning(entry: "Main.Real.run", found: false) == """
            warning: --entry Main.Real.run came to no method with a body in the given sources, \
            so the diagram is empty

            """)
        var written: [String] = []
        EntryNotFoundReporter.report(entry: "Svc.run", found: false) { written.append($0) }
        #expect(written.count == 1)
    }

    @Test("the commands warn of an entry they do not find, and not of one they do", arguments: [
        "sequence", "activity"
    ])
    func commandsWarn(command: String) throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swiftumlbridge-entry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "struct Real { func idle() {} }\n".write(
            to: directory.appendingPathComponent("Real.swift"), atomically: true, encoding: .utf8
        )
        for (entry, warns) in [("Real.missing", true), ("Real.idle", false)] {
            let result = try runCLI([command, ".", "--entry", entry, "--output", "consoleOnly"], in: directory)
            #expect(result.status == 0)
            #expect(result.output.contains("warning: --entry \(entry) came to no method") == warns, "\(result.output)")
        }
    }

    @Test("an entry that was found gets none")
    func silentWhenFound() {
        #expect(EntryNotFoundReporter.warning(entry: "Real.run", found: true) == nil)
        var written: [String] = []
        EntryNotFoundReporter.report(entry: "Real.run", found: true) { written.append($0) }
        #expect(written.isEmpty)
    }
}
