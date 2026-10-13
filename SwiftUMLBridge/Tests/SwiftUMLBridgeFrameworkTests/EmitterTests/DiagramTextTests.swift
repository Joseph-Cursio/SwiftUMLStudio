import Testing
import Foundation
@testable import SwiftUMLBridgeFramework

@Suite("DiagramText")
struct DiagramTextTests {

    // MARK: - base64plantuml padding branches

    @Test("base64plantuml handles 2-byte-remainder with one padding char")
    func base64plantumlTwoBytePadding() {
        // Provide exactly 2 bytes: exercises the byteIndex + 2 == count branch
        let bytes: [UInt8] = [0xAB, 0xCD]
        let data = NSData(bytes: bytes, length: bytes.count)
        let dt = DiagramText(rawValue: "")
        let encoded = dt.base64plantuml(data)
        // Two input bytes → three encoded chars + one '=' padding
        let encodedBytes = Array(encoded.utf8)
        #expect(encodedBytes.last == 61) // '=' is ASCII 61
        #expect(encodedBytes.count % 4 == 0)
    }

    @Test("base64plantuml handles 3-byte-aligned input with no padding")
    func base64plantumlNoPadding() {
        let bytes: [UInt8] = [0x01, 0x02, 0x03]
        let data = NSData(bytes: bytes, length: bytes.count)
        let dt = DiagramText(rawValue: "")
        let encoded = dt.base64plantuml(data)
        // Three input bytes → four encoded chars, no padding
        let encodedBytes = Array(encoded.utf8)
        #expect(encodedBytes.last != 61)
        #expect(encodedBytes.count == 4)
    }

    @Test("base64plantuml handles 1-byte-remainder with two padding chars")
    func base64plantumlOneBytePadding() {
        let bytes: [UInt8] = [0xFF]
        let data = NSData(bytes: bytes, length: bytes.count)
        let dt = DiagramText(rawValue: "")
        let encoded = dt.base64plantuml(data)
        // One input byte → two encoded chars + two '=' padding
        let encodedBytes = Array(encoded.utf8)
        #expect(encodedBytes.filter { $0 == 61 }.count == 2)
        #expect(encodedBytes.count % 4 == 0)
    }

    // MARK: - encodedValue round trip (#57)

    /// Text the encoder once truncated or dropped. Multi-byte characters lost the last
    /// `utf8.count - count` bytes, `\r\n` among them, and text that did not compress below its
    /// own length encoded to `""`. The ASCII diagram is the control that always passed.
    static let roundTripTexts = [
        "@startuml\nclass Foo\nclass Bar\nFoo --> Bar\n@enduml",
        "@startuml\nclass Café\nclass Naïve\nCafé --> Naïve\n@enduml",
        "@startuml\nclass 日本語クラス\nclass 中文类型\n@enduml",
        "@startuml\nnote \"🚀 launch 🚀\"\n@enduml",
        "@startuml\r\nclass Foo\r\nclass Bar\r\nFoo --> Bar\r\n@enduml\r\n",
        "@startuml\n@enduml",
        "@startuml\nA --> B : conforms\n@enduml",
        "ab",
        "a",
        "é",
        "🚀"
    ]

    @Test("encodedValue decodes back to exactly the raw text", arguments: roundTripTexts)
    func encodedValueRoundTrips(_ raw: String) {
        let encoded = DiagramText(rawValue: raw).encodedValue
        #expect(PlantUMLTextDecoding.decode(encoded) == raw)
    }

    @Test("encodedValue round-trips a large diagram that compresses poorly")
    func encodedValueRoundTripsLargeText() {
        // Pseudo-random printable text deflates to most of its own length, so the payload
        // spans many DEFLATE blocks and outgrows any small fixed buffer.
        var state: UInt32 = 57
        let characters = (0..<100_000).map { _ -> Character in
            state = state &* 1_664_525 &+ 1_013_904_223
            return Character(Unicode.Scalar(UInt8(33 + (state >> 24) % 94)))
        }
        let raw = "@startuml\nnote \"Café " + String(characters) + "\"\n@enduml"
        #expect(PlantUMLTextDecoding.decode(DiagramText(rawValue: raw).encodedValue) == raw)
    }

    @Test("encodeText round-trips a generated class diagram with non-ASCII names")
    func generatedClassDiagramRoundTrips() {
        let script = ClassDiagramGenerator().generateScript(
            for: "struct Café { let naïve: Int }", with: Configuration(format: .plantuml))
        #expect(script.text.contains("naïve"))
        #expect(PlantUMLTextDecoding.decode(script.encodeText()) == script.text)
    }

    @Test("hexEncoded is ~h and every UTF-8 byte in lowercase hex")
    func hexEncodedSpellsEveryUTF8Byte() {
        let text = DiagramText(rawValue: "")
        #expect(text.hexEncoded("@startuml\nclass Café\n@enduml")
            == "~h407374617274756d6c0a636c61737320436166c3a90a40656e64756d6c")
        #expect(text.hexEncoded("") == "~h")
    }

    // MARK: - description and debugDescription

    @Test("description returns the same value as encodedValue")
    func descriptionEqualsEncodedValue() {
        let text = DiagramText(rawValue: String(repeating: "B", count: 60))
        #expect(text.description == text.encodedValue)
    }

    @Test("debugDescription contains raw value and encoded value")
    func debugDescriptionContainsBothValues() {
        let raw = String(repeating: "C", count: 60)
        let text = DiagramText(rawValue: raw)
        #expect(text.debugDescription.contains(raw))
        #expect(text.debugDescription.contains(text.encodedValue))
    }
}
