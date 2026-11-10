import Foundation
@testable import swiftumlbridge
import SwiftUMLBridgeFramework
import Testing

// Argument parsing only — no command is `run()`, so nothing here parses Swift
// source or writes output. What is under test is the contract between what a
// user types and what the command ends up holding: defaults, required options,
// and the flag precedence the commands document in comments but never asserted.

// MARK: - --format help

@Suite("--format help text")
struct FormatHelpTests {

    /// ArgumentParser appends `(values: …)` from `DiagramFormat.allCases`, so a
    /// hand-written list in the help string can only go stale beside it. Each
    /// format named once means the generated list is the only one.
    @Test("names every format exactly once", arguments: [
        "classdiagram", "sequence", "deps", "activity", "state", "er", "component"
    ])
    func listsEveryFormatOnce(commandName: String) throws {
        // Looked up by name rather than listed as types, so this file needs no
        // `import ArgumentParser` for `ParsableCommand.Type`.
        let subcommand = try #require(CLI.configuration.subcommands.first {
            $0.configuration.commandName == commandName
        })
        let help = CLI.helpMessage(for: subcommand, columns: 1_000)
        let formatLine = try #require(help.split(separator: "\n").first {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("--format <format>")
        })

        for format in DiagramFormat.allCases {
            #expect(formatLine.components(separatedBy: format.rawValue).count - 1 == 1, "\(format)")
        }
    }
}
