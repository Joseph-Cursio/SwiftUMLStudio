@testable import swiftumlbridge
import Testing

// Argument parsing only — no command is `run()`, so nothing here parses Swift
// source or writes output. What is under test is the contract between what a
// user types and what the command ends up holding: defaults, required options,
// and the flag precedence the commands document in comments but never asserted.

// MARK: - state

@Suite("state command parsing")
struct StateCommandParsingTests {

    @Test("defaults to neither listing nor targeting a state machine")
    func defaults() throws {
        let command = try CLI.StateCommand.parse([])

        #expect(command.list == false)
        #expect(command.state == nil)
    }

    @Test("--list is a flag, --state takes a value")
    func listAndState() throws {
        let listing = try CLI.StateCommand.parse(["--list"])
        let targeted = try CLI.StateCommand.parse(["--state", "Light.Phase"])

        #expect(listing.list)
        #expect(targeted.state == "Light.Phase")
    }

    /// Not mutually exclusive at the parser level — both can be supplied.
    /// Recorded rather than asserted as correct: if the intent is that `--list`
    /// wins, that belongs in a `validate()`, and this test will need updating.
    @Test("--list and --state together currently parse without complaint")
    func listAndStateTogetherParse() throws {
        let command = try CLI.StateCommand.parse(["--list", "--state", "Light.Phase"])

        #expect(command.list)
        #expect(command.state == "Light.Phase")
    }
}
