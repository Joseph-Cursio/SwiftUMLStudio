import Foundation
import Testing

/// `--entry` follows a chain of typealiases to its end, however long, as Swift does (#248): a
/// plain chain stopped after 9 links, and a chain whose every link reads one more first part,
/// as `typealias S1 = S2.In` does, after 8. Each source passes `swiftc -typecheck`.
@Suite("An entry through a long chain of typealiases")
struct LongAliasChainEntryTests {
    /// Both diagrams of `type.method` over `files`, written in that order.
    private static func both(_ files: [EntryFile], _ type: String, _ method: String) throws -> [String] {
        let (root, paths) = try EntryFixture.written(files)
        defer { try? FileManager.default.removeItem(at: root) }
        return EntryFixture.both(paths, type, method)
    }

    private static let real = "struct Real {\n    func run() { step() }\n    func step() {}\n}\n"

    @Test("a plain chain reaches the type's own body", arguments: [9, 10, 20])
    func plainChain(length: Int) throws {
        let links = (1...length).map { "typealias A\($0) = \($0 == 1 ? "Real" : "A\($0 - 1)")\n" }.joined()
        for text in try Self.both([("Pkg/A.swift", Self.real + links)], "A\(length)", "run") {
            #expect(text.contains("step()"), "\(text)")
        }
    }

    /// `S1` is `S2.In`, `S3.In.In`, and so on to `Real` with `In` nested 9 deep, each step
    /// reading one more first part through its alias.
    @Test("a chain that reads one more first part at each link reaches the type's own body")
    func dottedChain() throws {
        let depth = 9
        var source = "struct Real {\n"
        for level in 1...depth {
            source += String(repeating: "    ", count: level) + "struct In {\n"
        }
        let body = String(repeating: "    ", count: depth + 1)
        source += "\(body)func run() { step() }\n\(body)func step() {}\n"
        for level in (0...depth).reversed() {
            source += String(repeating: "    ", count: level) + "}\n"
        }
        source += (1...depth).map { "typealias S\($0) = S\($0 + 1).In\n" }.joined()
        source += "typealias S\(depth + 1) = Real\n"
        for text in try Self.both([("Pkg/S.swift", source)], "S1", "run") {
            #expect(text.contains("step()"), "\(text)")
        }
    }

    /// Swift rejects both; the entry must still come back.
    @Test("a cycle of aliases ends", arguments: [
        "typealias A = B\ntypealias B = A\n",
        "typealias A = B.X\ntypealias B = A.Y\n",
    ])
    func cycleEnds(aliases: String) throws {
        let texts = try Self.both([("Pkg/A.swift", Self.real + aliases)], "A", "run")
        #expect(texts.count == 2)
    }
}
