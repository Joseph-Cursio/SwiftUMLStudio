import Foundation
import Synchronization
import Testing
import SwiftUMLBridgeFramework
@testable import swiftumlbridge

/// The warnings a loader printed.
private final class Warnings: Sendable {
    let lines = Mutex<[String]>([])
}

/// A config file that fails to decode used to be dropped whole, with nothing on stderr and exit
/// code 0, and a broken `--config` file fell back to the current directory's (#138).
@Suite("ConfigurationLoader")
struct ConfigurationLoaderTests {

    /// A fresh directory for each test's files.
    private static func makeDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swiftumlbridge-config-loader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func write(_ yaml: String, to url: URL) throws {
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    }

    static let badColour = "texts:\n  title: Mine\nrelationships:\n  inheritance:\n    style:\n"
        + "      lineStyle: plain\n      lineColor: \"#FF0000\"\n      textColor: black\n"
    static let colourReason = "invalid value at relationships.inheritance.style.lineColor: "
        + "'#FF0000' is not a colour name this tool knows"

    /// A loader that reads `discovered` when no `--config` is given, and records its warnings.
    private static func loader(discovered: URL, warnings: Warnings) -> ConfigurationLoader {
        var loader = ConfigurationLoader()
        loader.discoveredFile = discovered
        loader.warn = { line in warnings.lines.withLock { $0.append(line) } }
        return loader
    }

    @Test("a --config file that cannot be used fails the run, naming the path as typed and the reason")
    func explicitFileFails() throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("bad.yml")
        try Self.write(Self.badColour, to: file)
        let warnings = Warnings()

        #expect {
            try Self.loader(discovered: directory.appendingPathComponent(".swiftumlbridge.yml"), warnings: warnings)
                .load(file.path)
        } throws: { error in
            (error as? CLIError)?.description == "--config \(file.path): \(Self.colourReason)"
        }
        #expect(warnings.lines.withLock { $0 } == [])
    }

    @Test("a missing --config file fails the run")
    func missingExplicitFile() {
        let warnings = Warnings()
        #expect {
            try Self.loader(discovered: URL(fileURLWithPath: "/no/such/.swiftumlbridge.yml"), warnings: warnings)
                .load("no-such-config.yml")
        } throws: { error in
            (error as? CLIError)?.description == "--config no-such-config.yml: no such file"
        }
    }

    /// The current directory's file is not a fallback for a named one, however broken that is.
    @Test("a --config file is read, and the current directory's file is not")
    func explicitFileWins() throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let discovered = directory.appendingPathComponent(".swiftumlbridge.yml")
        try Self.write("texts:\n  title: Discovered\n", to: discovered)
        let file = directory.appendingPathComponent("named.yml")
        try Self.write("texts:\n  title: Named\n", to: file)
        let warnings = Warnings()

        let config = try Self.loader(discovered: discovered, warnings: warnings).load(file.path)

        #expect(config.texts?.title == "Named")
    }

    @Test("a current-directory file that cannot be used is ignored, with a warning")
    func discoveredFileWarns() throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let discovered = directory.appendingPathComponent(".swiftumlbridge.yml")
        try Self.write(Self.badColour, to: discovered)
        let warnings = Warnings()

        let config = try Self.loader(discovered: discovered, warnings: warnings).load(nil)

        #expect(config.texts == nil)
        #expect(warnings.lines.withLock { $0 } == ["warning: ignoring .swiftumlbridge.yml: \(Self.colourReason)\n"])
    }

    @Test("with no file in the current directory the defaults apply, without a warning")
    func noDiscoveredFile() throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let warnings = Warnings()

        let discovered = directory.appendingPathComponent(".swiftumlbridge.yml")
        let config = try Self.loader(discovered: discovered, warnings: warnings).load(nil)

        #expect(config.format == Configuration.default.format)
        #expect(warnings.lines.withLock { $0 } == [])
    }
}

/// The same, from the built executable in a real working directory, where `runCLI` reads stdout
/// and stderr through one pipe.
@Suite("CLI integration — a config file that cannot be used")
struct ConfigurationReportingTests {

    private static func makeProject(discovered: String?) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swiftumlbridge-config-reporting-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "struct User: Codable {}\n"
            .write(to: root.appendingPathComponent("User.swift"), atomically: true, encoding: .utf8)
        if let discovered {
            try discovered.write(
                to: root.appendingPathComponent(".swiftumlbridge.yml"), atomically: true, encoding: .utf8
            )
        }
        return root
    }

    static let arguments = ["User.swift", "--format", "plantuml", "--output", "consoleOnly"]

    @Test("a bad --config file stops the run, for every subcommand that reads one", arguments: [
        ["classdiagram"], ["deps", "--types"]
    ])
    func explicitFileFails(subcommand: [String]) throws {
        let root = try Self.makeProject(discovered: "texts:\n  title: Discovered\n")
        defer { try? FileManager.default.removeItem(at: root) }
        try "format: Mermaid\n".write(to: root.appendingPathComponent("bad.yml"), atomically: true, encoding: .utf8)

        let run = try runCLI(subcommand + Self.arguments + ["--config", "bad.yml"], in: root)

        #expect(run.status != 0)
        #expect(run.output.contains("Error: --config bad.yml: invalid value at format"), "\(run.output)")
        #expect(!run.output.contains("@startuml"), "\(run.output)")
    }

    @Test("a bad .swiftumlbridge.yml is ignored with a warning, and the diagram is drawn")
    func discoveredFileWarns() throws {
        let root = try Self.makeProject(discovered: "texts:\n  title: Discovered\nformat: Mermaid\n")
        defer { try? FileManager.default.removeItem(at: root) }

        let run = try runCLI(["classdiagram"] + Self.arguments, in: root)

        #expect(run.status == 0, "\(run.output)")
        #expect(run.output.contains("warning: ignoring .swiftumlbridge.yml: invalid value at format"), "\(run.output)")
        #expect(run.output.contains("Codable <|-- User : inherits"), "\(run.output)")
        #expect(!run.output.contains("Discovered"), "\(run.output)")
    }

    /// The troubleshooting guide's way to run without the current directory's file.
    @Test("--config /dev/null is all defaults, and skips the current directory's file")
    func devNull() throws {
        let root = try Self.makeProject(discovered: "texts:\n  title: Discovered\n")
        defer { try? FileManager.default.removeItem(at: root) }

        let run = try runCLI(["classdiagram"] + Self.arguments + ["--config", "/dev/null"], in: root)

        #expect(run.status == 0, "\(run.output)")
        #expect(run.output.contains("Codable <|-- User : inherits"), "\(run.output)")
        #expect(!run.output.contains("Discovered"), "\(run.output)")
    }
}
