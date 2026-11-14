@testable import swiftumlbridge
import SwiftUMLBridgeFramework
import Testing

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
