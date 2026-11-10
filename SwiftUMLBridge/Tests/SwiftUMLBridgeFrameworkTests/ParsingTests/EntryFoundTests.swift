import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

/// An entry that comes to no method with a body draws an empty diagram, as one that calls or does
/// nothing does. The scripts tell the two apart, so the CLI can say which (#239).
@Suite("Whether an entry was found")
struct EntryFoundTests {
    private static let source = "struct Real {\n    func run() { step() }\n    func step() {}\n    func idle() {}\n}\n"

    /// Whether the sequence and the activity diagram of `type.method` found it.
    private static func found(_ type: String, _ method: String) throws -> [Bool] {
        let (root, paths) = try EntryFixture.written([("Pkg/Real.swift", source)])
        defer { try? FileManager.default.removeItem(at: root) }
        return [
            SequenceDiagramGenerator().generateScript(for: paths, entryType: type, entryMethod: method).foundEntry,
            ActivityDiagramGenerator().generateScript(for: paths, entryType: type, entryMethod: method).foundEntry,
        ]
    }

    @Test("a method with a body is found, though it calls nothing", arguments: ["run", "idle"])
    func found(method: String) throws {
        #expect(try Self.found("Real", method) == [true, true])
    }

    @Test("an entry that comes to no method with a body is not", arguments: [
        ("Real", "missing"), ("Missing", "run"), ("Lib.Real", "run")
    ])
    func notFound(type: String, method: String) throws {
        #expect(try Self.found(type, method) == [false, false])
    }

    @Test("an empty script found nothing")
    func emptyScripts() {
        #expect(!SequenceScript.empty.foundEntry)
        #expect(!ActivityScript.empty.foundEntry)
    }
}
