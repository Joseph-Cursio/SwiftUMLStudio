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
