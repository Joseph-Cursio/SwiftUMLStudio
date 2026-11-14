@testable import swiftumlbridge
import Testing

// Argument parsing only — no command is `run()`, so nothing here parses Swift
// source or writes output. What is under test is the contract between what a
// user types and what the command ends up holding: defaults, required options,
// and the flag precedence the commands document in comments but never asserted.

// MARK: - sequence

@Suite("sequence command parsing")
struct SequenceCommandParsingTests {

    @Test("--entry is required")
    func entryRequired() {
        #expect(throws: (any Error).self) { try CLI.SequenceCommand.parse([]) }
    }

    /// The help text promises "default: 3"; this is the only thing keeping that
    /// promise honest.
    @Test("depth defaults to 3")
    func depthDefault() throws {
        let command = try CLI.SequenceCommand.parse(["--entry", "Loader.load"])

        #expect(command.depth == 3)
        #expect(command.entry == "Loader.load")
    }

    @Test("--depth overrides the default")
    func depthOverride() throws {
        let command = try CLI.SequenceCommand.parse(["--entry", "A.b", "--depth", "7"])

        #expect(command.depth == 7)
    }

    @Test("a non-numeric --depth is rejected")
    func rejectsNonNumericDepth() {
        #expect(throws: (any Error).self) {
            try CLI.SequenceCommand.parse(["--entry", "A.b", "--depth", "deep"])
        }
    }

    /// Parsing accepts any string; the `Type.method` shape is enforced later by
    /// `parsedEntryPoint()`. Pinned so the split of responsibility stays clear.
    @Test("a malformed --entry parses, and is rejected only at use")
    func malformedEntryDefersValidation() throws {
        let command = try CLI.SequenceCommand.parse(["--entry", "nonsense"])

        #expect(command.entry == "nonsense")
        #expect(throws: CLIError.self) { try command.entry.parsedEntryPoint() }
    }
}
