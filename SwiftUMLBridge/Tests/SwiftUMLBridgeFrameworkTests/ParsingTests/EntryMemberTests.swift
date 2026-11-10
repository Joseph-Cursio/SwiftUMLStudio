import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

/// `T.method` names a member of `T` that can be named from outside it. A function local to a body has
/// `T`'s name around it and is not one, and a type local to a body cannot be named from outside.
@Suite("An entry means a member, and not a function local to a body")
struct EntryMemberTests {

    /// `run` in each of these is local to that body: `RealB().run()` does not compile.
    @Test("a function local to any body is no member", arguments: [
        "func other() { func run() { inner() }\n    run() }",
        "init() { func run() { inner() }\n    run() }",
        "deinit { func run() { inner() }\n    run() }",
        "var value: Int { func run() { inner() }\n    run()\n    return 1 }",
        "subscript(index: Int) -> Int { func run() { inner() }\n    run()\n    return index }",
        "let handler: () -> Void = { func run() { print(1) }\n    run() }",
    ])
    func localToAnyBody(host: String) throws {
        let (root, paths) = try EntryFixture.written([
            ("PkgB/Alias.swift", "final class RealB { \(host)\n    func inner() {} }\ntypealias Svc = RealB"),
            ("PkgA/Alias.swift", "struct RealA {}\ntypealias Svc = RealA"),
            ("PkgA/Ext.swift", "extension Svc {\n    func run() { step() }\n    func step() {}\n}"),
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        for text in EntryFixture.both(paths, "Svc", "run") {
            #expect(text.contains("RealA.run"), "\(text)")
            #expect(text.contains("step()"), "\(text)")
        }
    }

    @Test("a typealias of a type whose only method of that name is local draws nothing")
    func onlyLocalThroughAlias() throws {
        let (root, paths) = try EntryFixture.written([
            (
                "Pkg/Alias.swift",
                "struct RealB { func other() { func run() { inner() }\n    run() }\n    func inner() {} }\n"
                    + "typealias Svc = RealB"
            ),
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        for text in EntryFixture.both(paths, "Svc", "run") {
            #expect(text.contains("RealB.run"), "\(text)")
            #expect(!text.contains("inner()"), "\(text)")
        }
    }

    @Test("the activity diagram draws the member, not a function local to an initializer read first")
    func memberAfterLocal() throws {
        let (root, paths) = try EntryFixture.written([
            (
                "Pkg/Real.swift",
                "struct Real { init() { func run() { inLocal() }\n    run() }\n    func run() { inMember() }\n"
                    + "    func inLocal() {}\n    func inMember() {} }"
            ),
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let text = EntryFixture.activity(paths, "Real", "run")
        #expect(text.contains("inMember()"), "\(text)")
        #expect(!text.contains("inLocal"), "\(text)")
    }

    /// Beside a typealias the name is the typealias's, wherever the local type is, as Swift reads
    /// it outside that function. The list does not offer the local type, which cannot be named
    /// from outside the function (#235).
    @Test("a type local to a function is not what a typealias of its name means", arguments: ["run", "step"])
    func localTypeBesideAlias(method: String) throws {
        let (root, paths) = try EntryFixture.written([
            (
                "Pkg/Types.swift",
                "struct Xen {}\ntypealias Local = Xen\nstruct Host { func make() { struct Local {\n"
                    + "    func run() { step() }\n    func step() { last() }\n    func last() {} }\n"
                    + "    Local().run() } }"
            ),
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(!SequenceDiagramGenerator().findEntryPoints(for: paths).contains("Local.\(method)"))
        for text in EntryFixture.both(paths, "Local", method) {
            #expect(text.contains("Xen.\(method)"), "\(text)")
            #expect(!text.contains("last()"), "\(text)")
        }
    }

    private static let localState =
        "struct Parser { func parse() { struct State { func advance() { inLocal() }\n"
        + "    func inLocal() {} }\n    State().advance() } }"

    @Test("an activity diagram draws the type that can be named, past a type local to a function read first")
    func namedTypeAfterLocalType() throws {
        let (root, paths) = try EntryFixture.written([
            ("Pkg/A.swift", Self.localState),
            ("Pkg/B.swift", "struct State { func advance() { inMember() }\n    func inMember() {} }"),
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let text = EntryFixture.activity(paths, "State", "advance")
        #expect(text.contains("inMember()"), "\(text)")
        #expect(!text.contains("inLocal"), "\(text)")
    }

    private static let localLoc = "struct Loc { func run() { inLoc() }\n    func inLoc() {} }\n    Loc().run()"

    /// Each holds a `Loc` that can be named only inside it.
    private static let localHosts: [String] = [
        "func host() { \(localLoc) }",
        "let made: () -> Void = { \(localLoc) }",
        "var made: Int { \(localLoc)\n    return 1 }",
        "if true { \(localLoc) }",
        "switch 1 { case 1: \(localLoc)\n    default: break }",
    ]

    /// `Svc` is the top-level `Loc`, which has no `run`, as Swift says of `Svc().run()`.
    @Test("a typealias of a top-level type passes over a type of that name local to a body", arguments: localHosts)
    func localTypeBesideLaterBody(host: String) throws {
        let (root, paths) = try EntryFixture.written([
            ("PkgB/Alias.swift", "struct Loc {}\ntypealias Svc = Loc\n\(host)"),
            EntryFixture.withRun("C"),
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        for text in EntryFixture.both(paths, "Svc", "run") {
            #expect(text.contains("inC()"), "\(text)")
            #expect(!text.contains("inLoc"), "\(text)")
        }
    }

    @Test("with no other declaration, that typealias draws nothing rather than the local type's body",
          arguments: localHosts)
    func localTypeAlone(host: String) throws {
        let (root, paths) = try EntryFixture.written([
            ("PkgB/Alias.swift", "struct Loc {}\ntypealias Svc = Loc\n\(host)")
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        for text in EntryFixture.both(paths, "Svc", "run") {
            #expect(text.contains("Loc.run"), "\(text)")
            #expect(!text.contains("inLoc"), "\(text)")
        }
    }
}
