import Foundation

struct DiagramText: RawRepresentable {
    var rawValue: String

    /// The text in PlantUML's text encoding: its UTF-8 deflated, in PlantUML's base64 alphabet.
    var encodedValue: String {
        guard let compressedData = deflate(rawValue) else { return hexEncoded(rawValue) }
        return base64plantuml(compressedData)
    }
}

private extension DiagramText {
    /// Raw DEFLATE (RFC 1951) of every UTF-8 byte of `text`, or `nil` if the encoder fails.
    ///
    /// Foundation sizes the output itself. `compression_encode_buffer` was handed the
    /// `Character` count as both the source length and the destination capacity, so non-ASCII
    /// text lost its last `utf8.count - count` bytes, and text that did not compress below its
    /// own length encoded to `""` (#57). The encoder is still `COMPRESSION_ZLIB`, so text the
    /// old call read whole and fit still deflates to the same bytes.
    func deflate(_ text: String) -> NSData? {
        try? (Data(text.utf8) as NSData).compressed(using: .zlib)
    }
}

internal extension DiagramText {
    /// PlantUML's uncompressed text encoding: `~h`, then each UTF-8 byte of `text` in hex.
    ///
    /// Far longer than the deflated form, so it is used only if the encoder fails — a URL
    /// that renders the whole diagram rather than one with an empty payload.
    func hexEncoded(_ text: String) -> String {
        "~h" + text.utf8.map { String(format: "%02x", $0) }.joined()
    }

    func base64plantuml(_ compressedData: NSData) -> String {
        let bytes = [UInt8](compressedData)

        let encodingAlphabetTable: [UInt8] = [
            48, 49, 50, 51, 52, 53, 54, 55, 56, 57,
            65, 66, 67, 68, 69, 70, 71, 72, 73, 74,
            75, 76, 77, 78, 79, 80, 81, 82, 83, 84,
            85, 86, 87, 88, 89, 90, 97, 98, 99, 100,
            101, 102, 103, 104, 105, 106, 107, 108, 109, 110,
            111, 112, 113, 114, 115, 116, 117, 118, 119, 120,
            121, 122, 45, 95,
            61 // padding
        ]

        var encodedBytes: [UInt8] = []
        let padding = encodingAlphabetTable[64]

        var byteIndex = 0
        let count = bytes.count

        while byteIndex + 3 <= count {
            let one = bytes[byteIndex] >> 2
            let two = ((bytes[byteIndex] & 0b11) << 4) | ((bytes[byteIndex + 1] & 0b1111_0000) >> 4)
            let three = ((bytes[byteIndex + 1] & 0b0000_1111) << 2) | ((bytes[byteIndex + 2] & 0b1100_0000) >> 6)
            let four = bytes[byteIndex + 2] & 0b0011_1111
            encodedBytes.append(encodingAlphabetTable[Int(one)])
            encodedBytes.append(encodingAlphabetTable[Int(two)])
            encodedBytes.append(encodingAlphabetTable[Int(three)])
            encodedBytes.append(encodingAlphabetTable[Int(four)])
            byteIndex += 3
        }

        if byteIndex + 2 == count {
            let one = bytes[byteIndex] >> 2
            let two = ((bytes[byteIndex] & 0b11) << 4) | ((bytes[byteIndex + 1] & 0b1111_0000) >> 4)
            let three = ((bytes[byteIndex + 1] & 0b0000_1111) << 2)
            encodedBytes.append(encodingAlphabetTable[Int(one)])
            encodedBytes.append(encodingAlphabetTable[Int(two)])
            encodedBytes.append(encodingAlphabetTable[Int(three)])
            encodedBytes.append(padding)
        } else if byteIndex + 1 == count {
            let one = bytes[byteIndex] >> 2
            let two = ((bytes[byteIndex] & 0b11) << 4)
            encodedBytes.append(encodingAlphabetTable[Int(one)])
            encodedBytes.append(encodingAlphabetTable[Int(two)])
            encodedBytes.append(padding)
            encodedBytes.append(padding)
        } else {
            assert(byteIndex == count)
        }

        return String(decoding: encodedBytes, as: Unicode.UTF8.self)
    }
}

extension DiagramText: CustomStringConvertible {
    var description: String { encodedValue }
}

extension DiagramText: CustomDebugStringConvertible {
    var debugDescription: String { "\(rawValue) encoded is \(encodedValue)" }
}
