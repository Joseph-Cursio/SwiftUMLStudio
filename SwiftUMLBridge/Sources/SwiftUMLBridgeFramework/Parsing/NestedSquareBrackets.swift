import Foundation

/// Keeps a chain of nested `[` from taking time that doubles with each one (#148).
///
/// Since swift-syntax 602, SwiftParser checks each `[` for InlineArray sugar (`[3 of Int]`) by
/// reading the element after it as a type, then, with no `of`, reads the same element again as an
/// array or dictionary type. Each read goes into any `[` inside that element, so each `[` nested
/// in another's first element doubles the time: `[[…[1]…]]` 24 deep took 1.7 s a read in a
/// release build, and 40 to 65 times that in a debug one. SourceKit's parser makes the same two
/// reads. `maximumNestingLevel` does not bound it, as the lookahead never checks it.
///
/// So each parser is handed the source with every `[` nested more than `limit` deep in other `[`,
/// and the `]` that closes it, written as a space. Every other byte is kept, so offsets, lines
/// and columns are the same, and everything after the chain is still read. Real code nests `[` no
/// more than about 7 deep.
enum NestedSquareBrackets {
    /// How many `[` may be open around a `[` before it is written as a space. Each costs one
    /// doubling. A 10-deep chain of the costliest shape, `[(Int, [(Int, …)])]`, takes about a
    /// millisecond a read in a release build and under half a second in a debug one; at 12 the
    /// debug read took 1.6 s. Real code stays well inside it.
    static let limit = 10

    /// `source` as the parsers are given it: unchanged unless a `[` is nested more than `limit`
    /// deep, and then with each such `[` and its `]` written as a space. Where that happens, a
    /// notice naming `file`, when there is one, and the first such `[` is recorded in
    /// `SourceReadNotices`.
    static func readable(_ source: String, file: URL? = nil) -> String {
        var bytes = Array(source.utf8)
        guard bytes.lazy.filter({ $0 == UInt8(ascii: "[") }).count > limit else { return source }
        var scanner = Scanner(bytes: bytes)
        scanner.scan()
        guard let first = scanner.blanked.first else { return source }
        for offset in scanner.blanked {
            bytes[offset] = UInt8(ascii: " ")
        }
        SourceReadNotices.record(notice(file: file, source: source, offset: first))
        return String(bytes: bytes, encoding: .utf8) ?? source
    }

    /// The notice for a source whose first `[` past the limit is at UTF-8 `offset`.
    private static func notice(file: URL?, source: String, offset: Int) -> String {
        var line = 1
        var lineStart = 0
        for (position, byte) in source.utf8.prefix(offset).enumerated() where byte == UInt8(ascii: "\n") {
            line += 1
            lineStart = position + 1
        }
        // A column in UTF-8 bytes, as the compiler's diagnostics count it.
        let place = (file.map { "\($0.path):" } ?? "") + "\(line):\(offset - lineStart + 1)"
        return "\(place): a `[` nested more than \(limit) deep in other `[`. It and each such `[` after it "
            + "in the file were read as spaces, with their `]`, as each one doubles the time a parse takes"
    }
}

/// Finds the `[` nested more than `NestedSquareBrackets.limit` deep, and the `]` that close them.
///
/// It keeps a stack of what is open: `(`, `[` and `{`, string literals, and the interpolations in
/// them, which are read as code. Comments and strings are skipped. A closer pops back to the
/// opener it matches, so a stray `[` is dropped when the `{` or `(` around it closes, and does not
/// count for the rest of the file. A closer with nothing to match, or that would have to pop past
/// an interpolation's start, is ignored. Regex literals written `/…/` are read as code.
private struct Scanner {
    private enum Frame {
        case paren, brace
        case square(blanked: Bool)
        /// A string literal with this many `#` around it, on one line or in `"""`.
        case string(hashes: Int, multiline: Bool)
        /// `\(` in a string, read as code until its `)`.
        case interpolation
    }

    private let bytes: [UInt8]
    private var index = 0
    private var stack: [Frame] = []
    private var openSquares = 0
    /// The offsets of every `[` and `]` to write as a space, in order.
    private(set) var blanked: [Int] = []

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func scan() {
        while index < bytes.count {
            if case .string(let hashes, let multiline)? = stack.last {
                scanString(hashes: hashes, multiline: multiline)
            } else {
                scanCode()
            }
        }
    }

    private func byte(at offset: Int) -> UInt8? {
        offset < bytes.count ? bytes[offset] : nil
    }

    private func hashes(at offset: Int) -> Int {
        var count = 0
        while byte(at: offset + count) == UInt8(ascii: "#") { count += 1 }
        return count
    }

    private func isTripleQuote(at offset: Int) -> Bool {
        byte(at: offset) == UInt8(ascii: "\"") && byte(at: offset + 1) == UInt8(ascii: "\"")
            && byte(at: offset + 2) == UInt8(ascii: "\"")
    }

    // MARK: Code

    private mutating func scanCode() {
        if skipCommentOrLiteral() { return }
        let current = bytes[index]
        switch current {
        case UInt8(ascii: "("):
            stack.append(.paren)
        case UInt8(ascii: "{"):
            stack.append(.brace)
        case UInt8(ascii: "["):
            let blank = openSquares >= NestedSquareBrackets.limit
            if blank { blanked.append(index) }
            stack.append(.square(blanked: blank))
            openSquares += 1
        case UInt8(ascii: ")"), UInt8(ascii: "}"), UInt8(ascii: "]"):
            close(current)
        default:
            break
        }
        index += 1
    }

    /// Skips the comment or regex literal at `index`, or opens the string literal there. `false`
    /// when none starts there.
    private mutating func skipCommentOrLiteral() -> Bool {
        let current = bytes[index]
        let next = byte(at: index + 1)
        if current == UInt8(ascii: "/"), next == UInt8(ascii: "/") {
            while index < bytes.count, bytes[index] != UInt8(ascii: "\n") { index += 1 }
        } else if current == UInt8(ascii: "/"), next == UInt8(ascii: "*") {
            skipBlockComment()
        } else if current == UInt8(ascii: "\"") {
            openString(hashes: 0)
        } else if current == UInt8(ascii: "#") {
            let count = hashes(at: index)
            if byte(at: index + count) == UInt8(ascii: "\"") {
                index += count
                openString(hashes: count)
            } else if byte(at: index + count) == UInt8(ascii: "/") {
                skipExtendedRegex(hashes: count)
            } else {
                index += count
            }
        } else {
            return false
        }
        return true
    }

    /// Pops back to the opener `closer` matches, if one is open since the innermost interpolation.
    private mutating func close(_ closer: UInt8) {
        guard let match = stack.lastIndex(where: { frame in
            switch (frame, closer) {
            case (.paren, UInt8(ascii: ")")), (.interpolation, UInt8(ascii: ")")),
                 (.brace, UInt8(ascii: "}")), (.square, UInt8(ascii: "]")):
                return true
            default:
                return false
            }
        }) else { return }
        if let boundary = stack.lastIndex(where: { if case .interpolation = $0 { true } else { false } }),
           boundary > match {
            return
        }
        for frame in stack[match...] {
            if case .square = frame { openSquares -= 1 }
        }
        if case .square(blanked: true) = stack[match], closer == UInt8(ascii: "]") {
            blanked.append(index)
        }
        stack.removeSubrange(match...)
    }

    private mutating func skipBlockComment() {
        var depth = 0
        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "/"), byte(at: index + 1) == UInt8(ascii: "*") {
                depth += 1
                index += 2
            } else if bytes[index] == UInt8(ascii: "*"), byte(at: index + 1) == UInt8(ascii: "/") {
                depth -= 1
                index += 2
                if depth == 0 { return }
            } else {
                index += 1
            }
        }
    }

    /// Skips `#/…/#`, with as many `#` on each side, to its end or the end of the file.
    private mutating func skipExtendedRegex(hashes count: Int) {
        index += count + 1
        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "/"), hashes(at: index + 1) >= count {
                index += count + 1
                return
            }
            index += 1
        }
    }

    // MARK: Strings

    /// Opens the string literal whose first `"` is at `index`.
    private mutating func openString(hashes count: Int) {
        let multiline = isTripleQuote(at: index)
        index += multiline ? 3 : 1
        stack.append(.string(hashes: count, multiline: multiline))
    }

    private mutating func scanString(hashes count: Int, multiline: Bool) {
        let current = bytes[index]
        if current == UInt8(ascii: "\\"), hashes(at: index + 1) >= count {
            let next = index + 1 + count
            if byte(at: next) == UInt8(ascii: "(") {
                stack.append(.interpolation)
                index = next + 1
            } else {
                // An escape: the next character is part of the string, a `"` included.
                index = next + 1
            }
        } else if current == UInt8(ascii: "\""), !multiline || isTripleQuote(at: index) {
            let end = index + (multiline ? 3 : 1)
            if hashes(at: end) >= count {
                stack.removeLast()
                index = end + count
            } else {
                index += 1
            }
        } else if current == UInt8(ascii: "\n"), !multiline {
            // An unterminated string ends at its line, as the parser reads it.
            stack.removeLast()
            index += 1
        } else {
            index += 1
        }
    }
}
