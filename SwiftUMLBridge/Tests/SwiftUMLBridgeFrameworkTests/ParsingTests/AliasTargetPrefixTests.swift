import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// A typealias whose dotted target starts with another name for a type, as `typealias Svc = O.In`
/// after `typealias O = Real`, means the type `Real.In`, whose own body is filed under `In` and
/// `Real.In`. `--entry Svc.run` came to `O.In.run`, which nothing is filed under, and drew an empty
/// diagram (#239). Each source here passes `swiftc -module-name Main -typecheck`.
@Suite("An alias target through a prefix")
struct AliasTargetPrefixTests {
    /// Both diagrams of `type.method` over `files`, written in that order.
    private static func both(_ files: [EntryFile], _ type: String, _ method: String) throws -> [String] {
        let (root, paths) = try EntryFixture.written(files)
        defer { try? FileManager.default.removeItem(at: root) }
        return EntryFixture.both(paths, type, method)
    }

    private static let nested = "struct Real {\n    struct In {\n        func run() { step() }\n"
        + "        func step() {}\n    }\n}\n"

    @Test("a target whose first part is a typealias reaches the type's own body", arguments: [
        "typealias O = Real\ntypealias Svc = O.In\n",
        "typealias P = Real\ntypealias O = P\ntypealias Svc = O.In\n",
        "typealias Svc = O.In\ntypealias O = Real\n"
    ])
    func throughTypealias(aliases: String) throws {
        for text in try Self.both([("Pkg/Svc.swift", Self.nested + aliases)], "Svc", "run") {
            #expect(text.contains("step()"), "\(text)")
        }
    }

    @Test("the aliases may be in other files than the type")
    func acrossFiles() throws {
        let files: [EntryFile] = [
            ("Pkg/Real.swift", Self.nested), ("Pkg/O.swift", "typealias O = Real\n"),
            ("Pkg/Svc.swift", "typealias Svc = O.In\n")
        ]
        for text in try Self.both(files, "Svc", "run") {
            #expect(text.contains("step()"), "\(text)")
        }
    }

    @Test("an extension spelled as the target still reaches its method")
    func extensionSpelledAsTarget() throws {
        let source = "struct Real { struct In {} }\ntypealias O = Real\ntypealias Svc = O.In\n"
            + "extension O.In {\n    func run() { step() }\n    func step() {}\n}\n"
        for text in try Self.both([("Pkg/Svc.swift", source)], "Svc", "run") {
            #expect(text.contains("step()"), "\(text)")
        }
    }

    @Test("a name typed through a typealias prefix reaches the type's own body")
    func typedThroughPrefix() throws {
        let source = Self.nested + "typealias O = Real\n"
        for text in try Self.both([("Pkg/Svc.swift", source)], "O.In", "run") {
            #expect(text.contains("step()"), "\(text)")
        }
    }

    @Test("the names a target through a prefix comes to are listed after it")
    func entryTypes() {
        let source = Self.nested + "typealias P = Real\ntypealias O = P\ntypealias Svc = O.In\n"
        let file = URL(fileURLWithPath: "/tmp/Pkg/Svc.swift")
        let resolver = TypeAliasResolver(sources: [(file, source)])
        #expect(resolver.entryTypes(of: "Svc") == ["O.In", "Real.In", "Svc"])
    }
}
