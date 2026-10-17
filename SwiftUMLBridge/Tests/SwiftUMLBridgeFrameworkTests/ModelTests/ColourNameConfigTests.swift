import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// Colours written as `docs/user/reference.md` writes them (`DarkGray`, `AliceBlue`).
@Suite("Colour names in a config file")
struct ColourNameConfigTests {
    /// Writes `yaml` to a temporary file and decodes it the way the CLI does.
    private func decode(_ yaml: String) throws -> Configuration? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("colour-name-\(UUID().uuidString).yml")
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return ConfigurationProvider().decodeYml(config: url)
    }

    private func relationshipConfig(colour: String) -> String {
        """
        elements:
          exclude:
            - Hidden
        relationships:
          inheritance:
            label: "X"
            style:
              lineStyle: plain
              lineColor: \(colour)
              textColor: \(colour)
        """
    }

    /// `darkGray` passes today and is the guard: a fix should keep its bytes.
    @Test("a relationship colour decodes in any case, with the rest of the file",
          arguments: ["darkGray", "DarkGray", "darkgray", "DARKGRAY"])
    func relationshipColour(spelling: String) throws {
        let config = try decode(relationshipConfig(colour: spelling))
        let decoded = try #require(config)
        #expect(decoded.elements.exclude == ["Hidden"])
        #expect(decoded.relationships.inheritance?.label == "X")
        #expect(decoded.relationships.inheritance?.style?.plantuml == "#line:darkGray;line.plain;text:darkGray")
    }

    /// Names from reference.md's Colors section whose capitals differ from the case name
    /// in more than the first letter.
    @Test("reference.md's spellings decode to the enum's case",
          arguments: [("Firebrick", Color.fireBrick), ("Goldenrod", .goldenRod), ("Seashell", .seaShell)])
    func referenceSpelling(spelling: String, expected: Color) throws {
        let config = try decode(relationshipConfig(colour: spelling))
        let decoded = try #require(config)
        #expect(decoded.relationships.inheritance?.style?.lineColor == expected)
    }

    @Test("a stereotype spot colour decodes in PascalCase")
    func spotColour() throws {
        let config = try decode("""
            stereotypes:
              struct:
                spot:
                  character: "S"
                  color: AliceBlue
            """)
        let decoded = try #require(config)
        #expect(decoded.stereotypes.struct?.spot.color == .aliceBlue)
        #expect(decoded.stereotypes.struct?.plantuml == "<< (S, aliceBlue) >>")
    }

    /// The fixture writes every colour in PascalCase, as SwiftPlantUML did, and no test read it.
    @Test("the PascalCase fixture decodes, colours and all")
    func pascalCaseFixture() throws {
        let url = try #require(Bundle.module.resourceURL)
            .appendingPathComponent("TestData/ProjectMock/customConfigValid.yml")
        let decoded = try #require(ConfigurationProvider().decodeYml(config: url))
        #expect(decoded.theme?.rawValue == "hacker")
        #expect(decoded.relationships.inheritance?.style?.lineColor == .darkViolet)
        #expect(decoded.relationships.realize?.style?.plantuml == "#line:blue;line.dashed;text:blue")
        #expect(decoded.stereotypes.class?.spot.color == .aliceBlue)
        #expect(decoded.texts?.footer == "footerText")
    }
}
