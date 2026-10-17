import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// After `typealias Alias = Real`, a method declared in `extension Alias` is `Real`'s, and
/// `Alias.make()` calls into `Real`. Sequence and activity diagrams filed such a method under
/// `Alias`, so `Real.start` stopped at the call into the extension and `--entry Real.helper`
/// found nothing (#125).
@Suite("Call graphs through a typealias")
struct TypealiasCallGraphTests {
    private static let witness = """
        struct Real {
            func start() { helper() }
        }
        typealias Alias = Real
        extension Alias {
            func helper() { finish() }
            func finish() {}
        }
        """

    /// A fresh directory holding `files`, each name to its contents; removed by the caller.
    private func directory(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (name, contents) in files {
            try contents.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return root
    }

    private func sequence(_ root: URL, _ type: String, _ method: String) -> String {
        SequenceDiagramGenerator().generateScript(
            for: [root.path], entryType: type, entryMethod: method, with: Configuration(format: .mermaid)
        ).text
    }

    private func activity(_ root: URL, _ type: String, _ method: String) -> String {
        ActivityDiagramGenerator().generateScript(
            for: [root.path], entryType: type, entryMethod: method, with: Configuration(format: .mermaid)
        ).text
    }

    @Test("a sequence follows a call into an extension written through a typealias")
    func sequenceFollowsTheAlias() throws {
        let root = try directory(["Real.swift": Self.witness])
        defer { try? FileManager.default.removeItem(at: root) }
        let fromStart = sequence(root, "Real", "start")
        #expect(fromStart.contains("Real->>Real: helper()"), "\(fromStart)")
        #expect(fromStart.contains("Real->>Real: finish()"), "\(fromStart)")
        #expect(!fromStart.contains("Alias"), "\(fromStart)")
        #expect(sequence(root, "Real", "helper").contains("Real->>Real: finish()"))
    }

    @Test("an activity diagram finds a method declared in an extension written through a typealias")
    func activityFindsTheMethod() throws {
        let root = try directory(["Real.swift": Self.witness])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(activity(root, "Real", "helper").contains("\"finish()\""))
    }

    @Test("an entry written with the alias is the aliased type's")
    func entryWrittenWithTheAlias() throws {
        let root = try directory(["Real.swift": Self.witness])
        defer { try? FileManager.default.removeItem(at: root) }
        let viaAlias = sequence(root, "Alias", "helper")
        #expect(viaAlias.contains("Real->>Real: finish()"), "\(viaAlias)")
        #expect(activity(root, "Alias", "helper").contains("\"finish()\""))
    }

    @Test("entry points list the extension's methods under the aliased type")
    func entryPointsUseTheAliasedType() throws {
        let root = try directory(["Real.swift": Self.witness])
        defer { try? FileManager.default.removeItem(at: root) }
        let entries = SequenceDiagramGenerator().findEntryPoints(for: [root.path])
        #expect(entries == ["Real.finish", "Real.helper", "Real.start"])
        #expect(ActivityDiagramGenerator().findEntryPoints(for: [root.path]) == entries)
    }

    @Test("a call on the alias, in another file, calls into the aliased type")
    func receiverWrittenWithTheAlias() throws {
        let root = try directory([
            "Alias.swift": "struct Real { static func make() { Baz.hit() } }\ntypealias Alias = Real",
            "Caller.swift": "struct Caller { func go() { Alias.make() } }\nstruct Baz { static func hit() {} }"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let text = sequence(root, "Caller", "go")
        #expect(text.contains("Caller->>Real: make()"), "\(text)")
        #expect(text.contains("Real->>Baz: hit()"), "\(text)")
    }

    @Test("a nested alias and an alias chain are followed")
    func nestedAliasAndChain() throws {
        let root = try directory(["Real.swift": """
            struct Real { func start() { helper(); other() } }
            struct Container { typealias Element = Real }
            extension Container.Element { func helper() {} }
            typealias A1 = A2
            typealias A2 = Real
            extension A1 { func other() {} }
            """])
        defer { try? FileManager.default.removeItem(at: root) }
        let entries = SequenceDiagramGenerator().findEntryPoints(for: [root.path])
        #expect(entries == ["Real.helper", "Real.other", "Real.start"])
    }

    /// A `fileprivate` alias names its type only in its own file.
    @Test("a fileprivate alias in another file is not followed")
    func fileprivateAliasInAnotherFile() throws {
        let root = try directory([
            "A.swift": "struct Real {}\nfileprivate typealias Alias = Real\nextension Alias { func here() {} }",
            "B.swift": "extension Alias { func there() {} }"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let entries = SequenceDiagramGenerator().findEntryPoints(for: [root.path])
        #expect(entries == ["Alias.there", "Real.here"])
    }

    @Test("controls: without a typealias, names are as written")
    func controls() throws {
        let root = try directory(["Real.swift": """
            struct Real { func start() { helper() } }
            extension Real { func helper() { finish() }; func finish() {} }
            extension Other { func lone() {} }
            """])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(sequence(root, "Real", "start").contains("Real->>Real: finish()"))
        let entries = SequenceDiagramGenerator().findEntryPoints(for: [root.path])
        #expect(entries == ["Other.lone", "Real.finish", "Real.helper", "Real.start"])
    }
}
