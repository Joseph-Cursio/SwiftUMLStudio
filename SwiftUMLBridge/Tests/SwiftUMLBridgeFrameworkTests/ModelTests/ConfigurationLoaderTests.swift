import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// `loadConfiguration(at:)` says why a file cannot be used, where `getConfiguration(for:)` falls
/// back to the defaults without a word (#138).
@Suite("ConfigurationProvider.loadConfiguration")
struct ConfigurationLoaderTests {

    /// Writes `yaml` to a temporary file and loads it.
    private func load(_ yaml: String) throws -> Configuration {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("configuration-loader-\(UUID().uuidString).yml")
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return try ConfigurationProvider().loadConfiguration(at: url)
    }

    /// The reason `yaml` cannot be loaded, or `nil` when it loads.
    private func reason(_ yaml: String) throws -> String? {
        do {
            _ = try load(yaml)
            return nil
        } catch let error as ConfigurationLoadError {
            return error.reason
        }
    }

    private static let style = "relationships:\n  inheritance:\n    style:\n"

    /// Each value the issue found dropping its file, with the key and value it should name.
    static let invalid: [(yaml: String, reason: String)] = [
        (style + "      lineStyle: plain\n      lineColor: \"#FF0000\"\n      textColor: black\n",
         "invalid value at relationships.inheritance.style.lineColor: '#FF0000' is not a colour name this tool knows"),
        (style + "      lineStyle: dashed\n", "missing key 'lineColor' in relationships.inheritance.style"),
        (style + "      lineStyle: Dashed\n      lineColor: black\n      textColor: black\n",
         "invalid value at relationships.inheritance.style.lineStyle"),
        ("format: Mermaid\n", "invalid value at format"),
        ("elements:\n  havingAccessLevel: [Public]\n", "invalid value at elements.havingAccessLevel[0]"),
        ("elements:\n  showGenerics: maybe\n", "invalid value at elements.showGenerics"),
        ("stereotypes:\n  struct:\n    spot: {color: aliceBlue}\n",
         "missing key 'character' in stereotypes.struct.spot"),
        ("theme: hacker\ntheme: amiga\n", "duplicated key(s): 'theme'"),
        ("elements: [\n", "parser")
    ]

    @Test("a value that cannot be decoded is named, with its key", arguments: invalid)
    func namesTheKey(yaml: String, reason expected: String) throws {
        let reason = try #require(try reason(yaml), "loaded")
        #expect(reason.contains(expected), "\(reason)")
    }

    @Test("a file with no settings in it is all defaults",
          arguments: ["", "  \n", "# just a comment\n", "---\n", "~\n"])
    func noSettings(yaml: String) throws {
        let config = try load(yaml)
        #expect(config.format == Configuration.default.format)
        #expect(config.hideShowCommands == Configuration.default.hideShowCommands)
    }

    /// `String(contentsOf:)` cannot read a device; the troubleshooting guide passes this one.
    @Test("/dev/null is all defaults")
    func devNull() throws {
        let config = try ConfigurationProvider().loadConfiguration(at: URL(fileURLWithPath: "/dev/null"))
        #expect(config.format == Configuration.default.format)
    }

    @Test("a file that loads gives its settings")
    func loadsSettings() throws {
        let config = try load("format: mermaid\ntexts:\n  title: T\nrelationships:\n  inheritance:\n    label: X\n")
        #expect(config.format == .mermaid)
        #expect(config.texts?.title == "T")
        #expect(config.relationships.inheritance?.label == "X")
    }

    /// Unknown keys are still ignored: the README and the migration guide write some.
    @Test("an unknown key is ignored")
    func unknownKey() throws {
        #expect(try reason("elemnts:\n  exclude: [User]\nelements:\n  exlude: [User]\n") == nil)
    }

    @Test("a missing file is reported as missing")
    func missingFile() throws {
        let url = URL(fileURLWithPath: "/no/such/directory/config.yml")
        #expect {
            try ConfigurationProvider().loadConfiguration(at: url)
        } throws: { error in
            let loadError = error as? ConfigurationLoadError
            return loadError?.isMissingFile == true
                && loadError?.description == "/no/such/directory/config.yml: no such file"
        }
    }

    /// `getConfiguration(for:)` and `decodeYml(config:)` keep falling back; only an empty file,
    /// which is all defaults now, no longer counts as one that failed.
    @Test("decodeYml takes an empty file as the defaults")
    func decodeYmlEmptyFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("empty-\(UUID().uuidString).yml")
        try "".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(ConfigurationProvider().decodeYml(config: url)?.format == Configuration.default.format)
    }
}
