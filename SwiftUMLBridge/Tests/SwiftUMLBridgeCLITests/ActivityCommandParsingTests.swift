import Foundation
@testable import swiftumlbridge
import SwiftUMLBridgeFramework
import Testing

// Argument parsing only — no command is `run()`, so nothing here parses Swift
// source or writes output. What is under test is the contract between what a
// user types and what the command ends up holding: defaults, required options,
// and the flag precedence the commands document in comments but never asserted.

// MARK: - activity

@Suite("activity command parsing")
struct ActivityCommandParsingTests {

    @Test("--entry is required")
    func entryRequired() {
        #expect(throws: (any Error).self) { try CLI.ActivityCommand.parse([]) }
    }

    @Test("entry and paths are both captured")
    func capturesEntryAndPaths() throws {
        let command = try CLI.ActivityCommand.parse(["Sources", "--entry", "Loader.load"])

        #expect(command.entry == "Loader.load")
        #expect(command.paths == ["Sources"])
    }
}
