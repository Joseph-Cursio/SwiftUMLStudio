import Foundation
import Testing
import SwiftUMLBridgeFramework
@testable import swiftumlbridge

// MARK: - Package root

/// `--package` is read against the current directory with each `..` removed by text (#141).
/// `PackageRootPathTests` runs the built executable from a real working directory; these run
/// in-process, where coverage can see them, against absolute paths.
@Suite("String.packageRootURL")
struct PackageRootURLTests {

    /// A fresh directory holding `Pkg` and a symlink `lnk` to `Other/Deep`.
    private static func makeRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swiftumlbridge-package-root-url-\(UUID().uuidString)")
        let deep = root.appendingPathComponent("Other/Deep")
        for directory in [root.appendingPathComponent("Pkg"), deep] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("lnk"), withDestinationURL: deep)
        return root
    }

    @Test("each .. is removed by text, without following a symlink before it")
    func removesDotDotByText() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let expected = root.appendingPathComponent("Pkg").path

        #expect(try (root.path + "/Other/../Pkg").packageRootURL().path == expected)
        #expect(try (root.path + "/lnk/../Pkg").packageRootURL().path == expected)
        #expect(try (root.path + "/Pkg/").packageRootURL().path == expected)
    }

    @Test("a missing directory is reported by the path as typed")
    func missingDirectory() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let typed = root.path + "/Pkg/../NoSuchPkg"

        #expect(throws: CLIError.self) { try typed.packageRootURL() }
        #expect(CLIError.packageDirectoryNotFound(path: typed).description == "--package \(typed): no such directory")
    }

    @Test("a file is not a package directory")
    func fileIsRejected() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Package.swift")
        try "".write(to: file, atomically: true, encoding: .utf8)

        #expect(throws: CLIError.self) { try file.path.packageRootURL() }
    }
}

// MARK: - Entry-point parsing

/// `Type.method` is the contract for `--entry` on the sequence and activity
/// commands. Everything the user can type reaches this function, so its
/// rejection behaviour is the CLI's whole input validation for that option.
@Suite("String.parsedEntryPoint")
struct ParsedEntryPointTests {

    @Test("a well-formed entry point splits into type and method")
    func splitsWellFormed() throws {
        let (type, method) = try "Loader.load".parsedEntryPoint()

        #expect(type == "Loader")
        #expect(method == "load")
    }

    @Test("a bare type name is rejected")
    func rejectsBareType() {
        #expect(throws: CLIError.self) { try "Loader".parsedEntryPoint() }
    }

    /// A method of a nested type, as `extension NS.Real { func run() }`, is listed as `NS.Real.run`,
    /// so the last dot separates the method (#234). A module-qualified name reads the same way,
    /// as a type `MyModule.Loader`, and draws an empty diagram rather than an error.
    @Test("a three-part name splits at the last dot", arguments: [
        ("NS.Real.run", "NS.Real", "run"),
        ("MyModule.Loader.load", "MyModule.Loader", "load")
    ])
    func splitsThreePartsAtLastDot(entry: String, expectedType: String, expectedMethod: String) throws {
        let (type, method) = try entry.parsedEntryPoint()
        #expect(type == expectedType)
        #expect(method == expectedMethod)
    }

    @Test("an empty string is rejected")
    func rejectsEmpty() {
        #expect(throws: CLIError.self) { try "".parsedEntryPoint() }
    }

    /// Any part left empty, by a leading, trailing or doubled dot, is rejected: `EntryPointName`
    /// checks every part, so `Loader..load` cannot read as a type `Loader.`.
    @Test("a dangling or doubled dot is rejected", arguments: ["Loader.", ".load", ".", "..", "Loader..load"])
    func rejectsDanglingDot(input: String) {
        #expect(throws: CLIError.self) { try input.parsedEntryPoint() }
    }

    @Test("the thrown error is specifically invalidEntry")
    func throwsInvalidEntry() {
        do {
            _ = try "nope".parsedEntryPoint()
            Issue.record("expected a throw")
        } catch let error as CLIError {
            #expect(error.description == CLIError.invalidEntry.description)
        } catch {
            Issue.record("expected CLIError, got \(error)")
        }
    }
}

// MARK: - Output routing

@Suite("ClassDiagramOutput presenter routing")
struct PresenterRoutingTests {

    @Test("consoleOnly routes to the console presenter")
    func consoleRouting() {
        let output: ClassDiagramOutput? = .consoleOnly
        #expect(output.presenter is ConsolePresenter)
    }

    @Test("browserImageOnly routes to the browser presenter")
    func browserImageRouting() {
        let output: ClassDiagramOutput? = .browserImageOnly
        #expect(output.presenter is BrowserPresenter)
    }

    @Test("browser routes to the browser presenter")
    func browserRouting() {
        let output: ClassDiagramOutput? = .browser
        #expect(output.presenter is BrowserPresenter)
    }

    /// Omitting `--output` must open the browser, matching the documented
    /// default. This is the branch a user hits by typing nothing at all.
    @Test("no --output defaults to the browser presenter")
    func defaultRouting() {
        let output: ClassDiagramOutput? = nil
        #expect(output.presenter is BrowserPresenter)
    }
}

// MARK: - Configuration resolution

@Suite("CommonDiagramOptions.resolvedConfiguration")
struct ResolvedConfigurationTests {

    @Test("--format overrides the configuration's format")
    func formatOverrides() throws {
        let options = try CommonDiagramOptions.parse(["--format", "mermaid"])

        #expect(try options.resolvedConfiguration().format == .mermaid)
    }

    @Test("omitting --format leaves the configuration's own format in place")
    func formatDefaults() throws {
        let options = try CommonDiagramOptions.parse([])
        let expected = ConfigurationProvider().getConfiguration(for: nil).format

        #expect(try options.resolvedConfiguration().format == expected)
    }

    @Test("every format value the help text advertises is accepted")
    func acceptsAdvertisedFormats() throws {
        for format in ["plantuml", "mermaid"] {
            let options = try CommonDiagramOptions.parse(["--format", format])
            #expect(options.format?.rawValue == format)
        }
    }

    @Test("an unknown --format value is rejected")
    func rejectsUnknownFormat() {
        #expect(throws: (any Error).self) {
            try CommonDiagramOptions.parse(["--format", "not-a-format"])
        }
    }

    @Test("every output value the help text advertises is accepted")
    func acceptsAdvertisedOutputs() throws {
        for output in ClassDiagramOutput.allCases {
            let options = try CommonDiagramOptions.parse(["--output", output.rawValue])
            #expect(options.output == output)
        }
    }
}
