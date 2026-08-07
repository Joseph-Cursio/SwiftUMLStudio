import Foundation
import Testing
import SwiftUMLBridgeFramework
@testable import swiftumlbridge

// Argument parsing only — no command is `run()`, so nothing here parses Swift
// source or writes output. What is under test is the contract between what a
// user types and what the command ends up holding: defaults, required options,
// and the flag precedence the commands document in comments but never asserted.

typealias CLI = SwiftUMLBridgeCLI

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

// MARK: - deps

@Suite("deps command parsing")
struct DepsCommandParsingTests {

    private func parse(_ arguments: [String]) throws -> CLI.DepsCommand {
        try CLI.DepsCommand.parse(arguments)
    }

    @Test("defaults to a type-level graph with no filters")
    func defaults() throws {
        let command = try parse([])

        #expect(command.modules == false)
        #expect(command.types == false)
        #expect(command.publicOnly == false)
        #expect(command.exclude.isEmpty)
        #expect(command.package == nil)
    }

    /// `run()` resolves the mode as `modules ? .modules : .types`, so passing
    /// both flags is not an error — `--modules` wins. Pinned because the
    /// precedence lives in a one-line comment and is otherwise invisible.
    @Test("--modules and --types together is accepted, with modules winning")
    func modulesWinsOverTypes() throws {
        let command = try parse(["--modules", "--types"])

        #expect(command.modules)
        #expect(command.types)
        // Mirrors the resolution in `run()`.
        #expect((command.modules ? DepsMode.modules : .types) == .modules)
    }

    @Test("--types alone selects the type-level graph")
    func typesAlone() throws {
        let command = try parse(["--types"])

        #expect((command.modules ? DepsMode.modules : .types) == .types)
    }

    @Test("repeated --exclude values accumulate")
    func excludeAccumulates() throws {
        let command = try parse(["--exclude", "Tests", "--exclude", "Generated"])

        #expect(command.exclude == ["Tests", "Generated"])
    }

    @Test("positional paths are collected")
    func collectsPaths() throws {
        let command = try parse(["Sources", "Tests"])

        #expect(command.paths == ["Sources", "Tests"])
    }

    @Test("--package is accepted alongside positional paths, which it overrides")
    func packageWithPaths() throws {
        let command = try parse(["Sources", "--package", "/tmp/Pkg"])

        #expect(command.package == "/tmp/Pkg")
        #expect(command.paths == ["Sources"], "paths still parse; run() prefers --package")
    }
}

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

// MARK: - er

@Suite("er command parsing")
struct ERCommandParsingTests {

    @Test("paths are optional and collected when given")
    func paths() throws {
        #expect(try CLI.ERCommand.parse([]).paths.isEmpty)
        #expect(try CLI.ERCommand.parse(["Models", "Store.xcdatamodeld"]).paths
            == ["Models", "Store.xcdatamodeld"])
    }
}

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
