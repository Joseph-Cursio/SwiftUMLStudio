import Foundation
import Testing

// `classdiagram` runs whose file selection comes out empty, made by the built
// `swiftumlbridge` executable from inside a throwaway project.
//
// `FileCollector` reads an empty *path list* as "the current directory".
// `classdiagram` collected and filtered its files, then handed the result to a
// generator that collected them again — so a selection filtered down to
// nothing became every Swift file in the cwd. Seeing that needs a real cwd
// holding a type to leak, hence a subprocess: changing this process's working
// directory would move every test running in parallel along with it.
//
// As in `CommandRunIntegrationTests`, every run passes `--output consoleOnly`;
// the default presenter opens a browser.

/// Writes a project with one Swift file, `Sources/App.swift` declaring
/// `InCwdType`, and an `Empty/` directory holding no Swift files, into a fresh
/// temporary directory and returns its root.
private func makeTemporaryProject() throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("swiftumlbridge-cli-project-\(UUID().uuidString)")
    let sources = root.appendingPathComponent("Sources")

    try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent("Empty"), withIntermediateDirectories: true
    )
    try "struct InCwdType {}"
        .write(to: sources.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)

    return root
}

/// One way a `classdiagram` run can be left with no Swift files to diagram.
struct EmptySelection: CustomTestStringConvertible, Sendable {
    let label: String
    /// Contents of a config file to pass with `--config`, if any.
    let config: String?
    let arguments: [String]

    var testDescription: String { label }
}

@Suite("CLI integration — classdiagram file selection")
struct ClassDiagramFileSelectionTests {

    static let emptySelections = [
        EmptySelection(
            label: "files.include matching nothing",
            config: "files:\n  include:\n    - \"Nothing*.swift\"\n",
            arguments: []
        ),
        EmptySelection(
            label: "files.exclude matching everything",
            config: "files:\n  exclude:\n    - \"Sources/*.swift\"\n",
            arguments: []
        ),
        EmptySelection(
            label: "--exclude covering every path given",
            config: nil,
            arguments: ["Sources/App.swift", "--exclude", "Sources/*.swift"]
        ),
        EmptySelection(
            label: "a directory with no Swift files",
            config: nil,
            arguments: ["Empty"]
        )
    ]

    @Test("classdiagram fails rather than diagramming the cwd", arguments: emptySelections)
    func emptySelectionFails(selection: EmptySelection) throws {
        let root = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: root) }
        var arguments = ["classdiagram"] + selection.arguments
        if let config = selection.config {
            let configFile = root.appendingPathComponent("cfg.yml")
            try config.write(to: configFile, atomically: true, encoding: .utf8)
            arguments += ["--config", configFile.path]
        }
        arguments += ["--format", "mermaid", "--output", "consoleOnly"]

        let run = try runCLI(arguments, in: root)

        #expect(!run.output.contains("InCwdType"))
        #expect(run.status != 0)
        #expect(run.output.contains("No Swift files"))
    }

    /// Keeps the test above from passing vacuously: the same project and
    /// harness, with an include that matches, must diagram `InCwdType`.
    @Test("classdiagram diagrams the files a matching include selects")
    func matchingIncludeIsDiagrammed() throws {
        let root = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let configFile = root.appendingPathComponent("cfg.yml")
        try "files:\n  include:\n    - \"Sources/*.swift\"\n"
            .write(to: configFile, atomically: true, encoding: .utf8)

        let run = try runCLI([
            "classdiagram", "--config", configFile.path,
            "--format", "mermaid", "--output", "consoleOnly"
        ], in: root)

        #expect(run.status == 0)
        #expect(run.output.contains("InCwdType"))
    }
}
