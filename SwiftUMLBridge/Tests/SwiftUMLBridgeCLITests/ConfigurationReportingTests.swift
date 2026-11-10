import Foundation
@testable import swiftumlbridge
import SwiftUMLBridgeFramework
import Synchronization
import Testing

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

    @Test("--verbose says which config file is read")
    func verbose() throws {
        let root = try Self.makeProject(discovered: "texts:\n  title: Discovered\n")
        defer { try? FileManager.default.removeItem(at: root) }

        let run = try runCLI(["classdiagram"] + Self.arguments + ["--verbose"], in: root)
        let quiet = try runCLI(["classdiagram"] + Self.arguments, in: root)

        #expect(run.status == 0, "\(run.output)")
        #expect(run.output.contains("info: reading config file "), "\(run.output)")
        #expect(run.output.contains(".swiftumlbridge.yml\n"), "\(run.output)")
        #expect(!quiet.output.contains("info: "), "\(quiet.output)")
    }
}
