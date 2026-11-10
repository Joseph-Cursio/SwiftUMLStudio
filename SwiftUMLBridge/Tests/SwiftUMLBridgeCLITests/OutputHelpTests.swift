import Foundation
@testable import swiftumlbridge
import SwiftUMLBridgeFramework
import Testing

// Argument parsing only — no command is `run()`, so nothing here parses Swift
// source or writes output. What is under test is the contract between what a
// user types and what the command ends up holding: defaults, required options,
// and the flag precedence the commands document in comments but never asserted.

// MARK: - --output help and abstracts

@Suite("--output help text and abstracts")
struct OutputHelpTests {

    static let commandNames = ["classdiagram", "sequence", "deps", "activity", "state", "er", "component"]

    static func help(for commandName: String) throws -> String {
        let subcommand = try #require(CLI.configuration.subcommands.first {
            $0.configuration.commandName == commandName
        })
        return CLI.helpMessage(for: subcommand, columns: 1_000)
    }

    /// ArgumentParser appends `(values: …)` from `ClassDiagramOutput.allCases`, so the help
    /// string lists none itself (#165). Whole words are counted, as `browser` is inside
    /// `browserImageOnly`.
    @Test("names every output once, as a destination", arguments: commandNames)
    func listsEveryOutputOnce(commandName: String) throws {
        let help = try Self.help(for: commandName)
        let outputLine = try #require(help.split(separator: "\n").first {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("--output <output>")
        })
        let words = outputLine.split { !$0.isLetter }.map(String.init)

        #expect(outputLine.contains("Output destination."))
        for output in ClassDiagramOutput.allCases {
            #expect(words.filter { $0 == output.rawValue }.count == 1, "\(output)")
        }
    }

    /// The emitters of these subcommands print Mermaid text for some formats without a warning,
    /// so the help says which (#165).
    @Test("says which formats print Mermaid text", arguments: [
        ("sequence", HelpNotes.mermaidForNomnoml),
        ("activity", HelpNotes.mermaidForNomnoml),
        ("component", HelpNotes.mermaidForNomnoml),
        ("state", HelpNotes.mermaidForNomnomlAndSVG),
        ("er", HelpNotes.mermaidForNomnomlAndSVG),
    ])
    func notesMermaidFallback(commandName: String, note: String) throws {
        #expect(try Self.help(for: commandName).contains(note))
    }

    @Test("classdiagram and deps draw every format, so their help has no fallback note",
          arguments: ["classdiagram", "deps"])
    func noFallbackNote(commandName: String) throws {
        #expect(!(try Self.help(for: commandName).contains("print Mermaid text")))
    }

    @Test("the class diagram abstract names no format")
    func classDiagramAbstract() {
        let abstract = CLI.ClassDiagramCommand.configuration.abstract
        for format in DiagramFormat.allCases {
            #expect(!abstract.lowercased().contains(format.rawValue), "\(format)")
        }
    }

    @Test("the ER abstract names all four model sources")
    func erAbstract() {
        let abstract = CLI.ERCommand.configuration.abstract
        for source in ["SwiftData", "Core Data", "GRDB", "SQLite.swift"] {
            #expect(abstract.contains(source), "\(source)")
        }
    }
}
