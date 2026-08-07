import Foundation
import Testing
import SwiftUMLBridgeFramework
@testable import swiftumlbridge

// End-to-end runs of each subcommand against the on-disk fixtures: parse real
// arguments, execute `run()`, let the whole pipeline work — file collection,
// parsing, model building, emitting, presenting.
//
// Every case passes `--output consoleOnly`. That is not incidental: the default
// presenter is `BrowserPresenter`, which opens a browser window. A test that
// forgot the flag would spray browser tabs across the machine running it, so
// the helpers below take the flag rather than leaving it to each call site.
//
// These are slower than the parsing tests — real SourceKitten and SwiftSyntax
// passes — so each targets the smallest fixture subdirectory that exercises it.

// MARK: - Fixture paths

/// `TestFixtures/SampleProject/...` lives at the repo root, a sibling of the
/// SwiftUMLBridge package. Walk up four levels from this file:
/// SwiftUMLBridgeCLITests → Tests → SwiftUMLBridge → repo root.
private func repoRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // SwiftUMLBridgeCLITests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // SwiftUMLBridge
        .deletingLastPathComponent()  // repo root
}

private func fixture(_ relativePath: String) -> String {
    repoRoot().appendingPathComponent("TestFixtures/SampleProject/\(relativePath)").path
}

/// Writes a minimal two-target package into a fresh temporary directory and
/// returns its root.
///
/// Deliberately *not* the SwiftUMLBridge package itself. Component diagrams are
/// produced by shelling out to `swift package describe`, and running that
/// against the package whose build directory `swift test` is currently holding
/// deadlocks on SwiftPM's lock — the test hangs indefinitely rather than
/// failing. A throwaway package has its own `.build`, so there is nothing to
/// contend over.
private func makeTemporaryPackage() throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("swiftumlbridge-cli-tests-\(UUID().uuidString)")
    let core = root.appendingPathComponent("Sources/Core")
    let app = root.appendingPathComponent("Sources/App")

    try FileManager.default.createDirectory(at: core, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)

    let manifest = """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "TempPkg",
            targets: [
                .target(name: "Core"),
                .executableTarget(name: "App", dependencies: ["Core"])
            ]
        )
        """
    try manifest.write(
        to: root.appendingPathComponent("Package.swift"),
        atomically: true, encoding: .utf8
    )
    try "public struct Engine { public init() {} }"
        .write(to: core.appendingPathComponent("Core.swift"), atomically: true, encoding: .utf8)
    try "print(\"hi\")"
        .write(to: app.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)

    return root
}

/// Confirms the fixtures are actually where the path walk expects. Without this
/// a wrong path would show up as every integration test "passing" against an
/// empty file list, which is the failure mode worth guarding hardest.
@Suite("CLI integration — fixture wiring")
struct FixtureWiringTests {

    @Test("the fixture directories the run tests depend on exist", arguments: [
        "Models", "Services", "StateMachines", "Persistence"
    ])
    func fixtureDirectoryExists(name: String) {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: fixture(name), isDirectory: &isDirectory
        )

        #expect(exists, "missing fixture directory: \(fixture(name))")
        #expect(isDirectory.boolValue)
    }

    @Test("the throwaway package is written with a manifest and two targets")
    func temporaryPackageIsWritable() throws {
        let root = try makeTemporaryPackage()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Package.swift").path
        ))
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Core/Core.swift").path
        ))
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/App/main.swift").path
        ))
    }
}

// MARK: - Runs

@Suite("CLI integration — command runs")
struct CommandRunIntegrationTests {

    @Test("classdiagram runs over the model fixtures")
    func runsClassDiagram() async throws {
        var command = try SwiftUMLBridgeCLI.ClassDiagramCommand.parse([
            fixture("Models"), "--output", "consoleOnly"
        ])

        try await command.run()
    }

    @Test("classdiagram runs in mermaid as well as the default format")
    func runsClassDiagramAsMermaid() async throws {
        var command = try SwiftUMLBridgeCLI.ClassDiagramCommand.parse([
            fixture("Models"), "--output", "consoleOnly", "--format", "mermaid"
        ])

        try await command.run()
    }

    @Test("deps runs at type level")
    func runsDepsTypes() async throws {
        var command = try SwiftUMLBridgeCLI.DepsCommand.parse([
            fixture("Services"), "--types", "--output", "consoleOnly"
        ])

        try await command.run()
    }

    @Test("deps runs at module level")
    func runsDepsModules() async throws {
        var command = try SwiftUMLBridgeCLI.DepsCommand.parse([
            fixture("Services"), "--modules", "--output", "consoleOnly"
        ])

        try await command.run()
    }

    /// `--public-only` and `--exclude` each rebuild `bridgeConfig.elements`, the
    /// second reading back what the first wrote. Running them together is the
    /// only way to catch one clobbering the other.
    @Test("deps runs with --public-only and --exclude combined")
    func runsDepsWithFilters() async throws {
        var command = try SwiftUMLBridgeCLI.DepsCommand.parse([
            fixture("Services"), "--public-only",
            "--exclude", "NotificationService", "--output", "consoleOnly"
        ])

        try await command.run()
    }

    @Test("sequence runs from a real entry point")
    func runsSequence() async throws {
        var command = try SwiftUMLBridgeCLI.SequenceCommand.parse([
            fixture("Services"), "--entry", "AuthService.login", "--output", "consoleOnly"
        ])

        try await command.run()
    }

    @Test("sequence rejects a malformed entry point at run time")
    func sequenceRejectsMalformedEntry() async throws {
        var command = try SwiftUMLBridgeCLI.SequenceCommand.parse([
            fixture("Services"), "--entry", "nodots", "--output", "consoleOnly"
        ])

        await #expect(throws: CLIError.self) { try await command.run() }
    }

    @Test("activity runs from a real entry point")
    func runsActivity() async throws {
        var command = try SwiftUMLBridgeCLI.ActivityCommand.parse([
            fixture("Services"), "--entry", "UserStore.findByEmail", "--output", "consoleOnly"
        ])

        try await command.run()
    }

    @Test("activity rejects a malformed entry point at run time")
    func activityRejectsMalformedEntry() async throws {
        var command = try SwiftUMLBridgeCLI.ActivityCommand.parse([
            fixture("Services"), "--entry", "nodots", "--output", "consoleOnly"
        ])

        await #expect(throws: CLIError.self) { try await command.run() }
    }

    @Test("state --list enumerates candidates")
    func runsStateList() async throws {
        var command = try SwiftUMLBridgeCLI.StateCommand.parse([
            fixture("StateMachines"), "--list", "--output", "consoleOnly"
        ])

        try await command.run()
    }

    @Test("state runs without --list, picking a candidate itself")
    func runsStateDefault() async throws {
        var command = try SwiftUMLBridgeCLI.StateCommand.parse([
            fixture("StateMachines"), "--output", "consoleOnly"
        ])

        try await command.run()
    }

    /// The identifier is checked against the discovered candidates, so an
    /// unknown one must fail loudly rather than emit an empty diagram.
    @Test("state reports an unknown identifier rather than emitting nothing")
    func stateRejectsUnknownIdentifier() async throws {
        var command = try SwiftUMLBridgeCLI.StateCommand.parse([
            fixture("StateMachines"), "--state", "Nope.NotAThing", "--output", "consoleOnly"
        ])

        await #expect(throws: CLIError.self) { try await command.run() }
    }

    @Test("er runs over SwiftData models")
    func runsER() async throws {
        var command = try SwiftUMLBridgeCLI.ERCommand.parse([
            fixture("Models"), "--output", "consoleOnly"
        ])

        try await command.run()
    }

    @Test("er runs over the GRDB and SQLite fixtures")
    func runsERPersistence() async throws {
        var command = try SwiftUMLBridgeCLI.ERCommand.parse([
            fixture("Persistence"), "--output", "consoleOnly"
        ])

        try await command.run()
    }

    @Test("component runs against a real package manifest")
    func runsComponent() async throws {
        let root = try makeTemporaryPackage()
        defer { try? FileManager.default.removeItem(at: root) }
        var command = try SwiftUMLBridgeCLI.ComponentCommand.parse([
            "--package", root.path, "--output", "consoleOnly"
        ])

        try await command.run()
    }

    @Test("component runs with test targets included")
    func runsComponentWithTestTargets() async throws {
        let root = try makeTemporaryPackage()
        defer { try? FileManager.default.removeItem(at: root) }
        var command = try SwiftUMLBridgeCLI.ComponentCommand.parse([
            "--package", root.path,
            "--include-test-targets", "--output", "consoleOnly"
        ])

        try await command.run()
    }

    /// Component diagrams are package-scoped; a directory with no manifest has
    /// nothing to read, and must say so rather than emit an empty diagram.
    @Test("component reports a missing package manifest")
    func componentRejectsMissingManifest() async throws {
        var command = try SwiftUMLBridgeCLI.ComponentCommand.parse([
            "--package", fixture("Models"), "--output", "consoleOnly"
        ])

        await #expect(throws: (any Error).self) { try await command.run() }
    }
}
