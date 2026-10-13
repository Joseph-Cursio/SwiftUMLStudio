import Foundation

/// Decodes PlantUML's text encoding, the inverse of `DiagramText.encodedValue` (#57).
///
/// Checking only that `encodeText()` was non-empty passed while non-ASCII diagrams lost their
/// tail and short ones encoded to `""`. Decoding the payload and comparing it with the text is
/// the check that sees both.
enum PlantUMLTextDecoding {

    /// The text `encoded` stands for, or `nil` when it is not PlantUML's alphabet over a raw
    /// DEFLATE stream of UTF-8.
    static func decode(_ encoded: String) -> String? {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_")
        var sextets: [UInt8] = []
        for character in encoded where character != "=" {
            guard let index = alphabet.firstIndex(of: character) else { return nil }
            sextets.append(UInt8(index))
        }
        var bytes: [UInt8] = []
        var index = 0
        while index + 1 < sextets.count {
            bytes.append((sextets[index] << 2) | (sextets[index + 1] >> 4))
            if index + 2 < sextets.count {
                bytes.append(((sextets[index + 1] & 0b1111) << 4) | (sextets[index + 2] >> 2))
            }
            if index + 3 < sextets.count {
                bytes.append(((sextets[index + 2] & 0b11) << 6) | sextets[index + 3])
            }
            index += 4
        }
        guard let inflated = try? (Data(bytes) as NSData).decompressed(using: .zlib) else { return nil }
        return String(data: inflated as Data, encoding: .utf8)
    }
}
