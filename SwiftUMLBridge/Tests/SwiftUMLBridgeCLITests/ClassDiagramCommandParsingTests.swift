import Foundation
@testable import swiftumlbridge
import SwiftUMLBridgeFramework
import Testing

// Argument parsing only — no command is `run()`, so nothing here parses Swift
// source or writes output. What is under test is the contract between what a
// user types and what the command ends up holding: defaults, required options,
// and the flag precedence the commands document in comments but never asserted.

// MARK: - classdiagram

@Suite("classdiagram command parsing")
struct ClassDiagramCommandParsingTests {

    @Test("defaults leave every filter unset")
    func defaults() throws {
        let command = try CLI.ClassDiagramCommand.parse([])

        #expect(command.exclude.isEmpty)
        #expect(command.format == nil)
        #expect(command.output == nil)
        #expect(command.package == nil)
        #expect(command.sdk == nil)
    }

    @Test("format and output are accepted")
    func formatAndOutput() throws {
        let command = try CLI.ClassDiagramCommand.parse([
            "--format", "mermaid", "--output", "consoleOnly"
        ])

        #expect(command.format == .mermaid)
        #expect(command.output == .consoleOnly)
    }
}
