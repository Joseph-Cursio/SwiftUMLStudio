@testable import swiftumlbridge
import Testing

// Argument parsing only — no command is `run()`, so nothing here parses Swift
// source or writes output. What is under test is the contract between what a
// user types and what the command ends up holding: defaults, required options,
// and the flag precedence the commands document in comments but never asserted.

// MARK: - component

@Suite("component command parsing")
struct ComponentCommandParsingTests {

    /// Component diagrams are package-scoped, so unlike every other subcommand
    /// `--package` is required rather than optional.
    @Test("--package is required")
    func packageRequired() {
        #expect(throws: (any Error).self) { try CLI.ComponentCommand.parse([]) }
    }

    @Test("test targets are excluded by default")
    func excludesTestTargetsByDefault() throws {
        let command = try CLI.ComponentCommand.parse(["--package", "/tmp/Pkg"])

        #expect(command.includeTestTargets == false)
        #expect(command.package == "/tmp/Pkg")
    }

    @Test("--include-test-targets opts in")
    func includeTestTargets() throws {
        let command = try CLI.ComponentCommand.parse([
            "--package", "/tmp/Pkg", "--include-test-targets"
        ])

        #expect(command.includeTestTargets)
    }
}
