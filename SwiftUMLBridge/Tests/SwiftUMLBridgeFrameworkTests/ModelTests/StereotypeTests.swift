import Testing
@testable import SwiftUMLBridgeFramework
import Foundation

@Suite("Stereotype")
struct StereotypeTests {

    // MARK: - Character: Codable

    @Test("Spot encodes and decodes via JSON round-trip")
    func spotJSONRoundTrip() throws {
        let spot = Spot(character: "C", color: .darkSeaGreen)
        let data = try JSONEncoder().encode(spot)
        let decoded = try JSONDecoder().decode(Spot.self, from: data)
        #expect(decoded.character == "C")
        #expect(decoded.color == .darkSeaGreen)
    }

    @Test("Character decodes from single-character JSON string")
    func characterDecodesFromSingleChar() throws {
        let json = Data(#"{"character":"S","color":"skyBlue"}"#.utf8)
        let spot = try JSONDecoder().decode(Spot.self, from: json)
        #expect(spot.character == "S")
    }

    @Test("Character decoding fails for empty string")
    func characterDecodingFailsForEmptyString() {
        let json = Data(#"{"character":"","color":"skyBlue"}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Spot.self, from: json)
        }
    }

    @Test("Character decoding fails for multi-character string")
    func characterDecodingFailsForMultiChar() {
        let json = Data(#"{"character":"AB","color":"skyBlue"}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Spot.self, from: json)
        }
    }

    @Test("Stereotype encodes and decodes via JSON round-trip")
    func stereotypeJSONRoundTrip() throws {
        let stereotype = Stereotype.struct
        let data = try JSONEncoder().encode(stereotype)
        let decoded = try JSONDecoder().decode(Stereotype.self, from: data)
        #expect(decoded.spot.character == stereotype.spot.character)
        #expect(decoded.name == stereotype.name)
    }
}
