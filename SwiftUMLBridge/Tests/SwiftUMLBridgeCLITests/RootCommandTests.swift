@testable import swiftumlbridge
import Testing

// Argument parsing only — no command is `run()`, so nothing here parses Swift
// source or writes output. What is under test is the contract between what a
// user types and what the command ends up holding: defaults, required options,
// and the flag precedence the commands document in comments but never asserted.

// MARK: - Root command

@Suite("swiftumlbridge root command")
struct RootCommandTests {

    @Test("advertises a version string")
    func hasVersion() {
        #expect(CLI.configuration.version.isEmpty == false)
    }

    /// Running `swiftumlbridge <paths>` with no subcommand generates a class
    /// diagram. That default is the documented entry experience.
    @Test("class diagram is the default subcommand")
    func defaultSubcommand() {
        #expect(CLI.configuration.defaultSubcommand == CLI.ClassDiagramCommand.self)
    }

    @Test("every documented subcommand is registered", arguments: [
        "classdiagram", "sequence", "deps", "activity", "state", "er", "component"
    ])
    func subcommandRegistered(name: String) {
        // Built with an explicit loop rather than `compactMap(\.configuration
        // .commandName)`: a key path through `[any ParsableCommand.Type]`
        // crashes SILGen in Swift 6.3.3 (swiftlang-6.3.3.1.3).
        var names: [String] = []
        for subcommand in CLI.configuration.subcommands {
            if let commandName = subcommand.configuration.commandName {
                names.append(commandName)
            }
        }

        #expect(names.contains(name), "\(name) is missing from the root command")
    }
}
