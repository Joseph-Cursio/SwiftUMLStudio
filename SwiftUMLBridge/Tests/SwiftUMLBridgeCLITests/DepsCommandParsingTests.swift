@testable import swiftumlbridge
import SwiftUMLBridgeFramework
import Testing

// Argument parsing only — no command is `run()`, so nothing here parses Swift
// source or writes output. What is under test is the contract between what a
// user types and what the command ends up holding: defaults, required options,
// and the flag precedence the commands document in comments but never asserted.

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
