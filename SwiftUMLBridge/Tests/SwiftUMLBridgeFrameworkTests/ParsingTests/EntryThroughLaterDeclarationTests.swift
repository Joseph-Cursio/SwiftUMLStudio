import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

typealias EntryFile = (path: String, contents: String)

/// Writes sources to disk and draws an entry from them, for the tests of what an entry means.
enum EntryFixture {
    /// `files`, written under a fresh directory, and their paths in the order they are to be read.
    static func written(_ files: [EntryFile]) throws -> (root: URL, paths: [String]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let urls = files.map { root.appendingPathComponent($0.path) }
        for (url, file) in zip(urls, files) {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try file.contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return (root, urls.map(\.path))
    }

    static func sequence(_ paths: [String], _ type: String, _ method: String) -> String {
        SequenceDiagramGenerator().generateScript(
            for: paths, entryType: type, entryMethod: method, with: Configuration(format: .mermaid)
        ).text
    }

    static func activity(_ paths: [String], _ type: String, _ method: String) -> String {
        ActivityDiagramGenerator().generateScript(
            for: paths, entryType: type, entryMethod: method, with: Configuration(format: .mermaid)
        ).text
    }

    /// Both diagrams of one entry, which are to mean the same method.
    static func both(_ paths: [String], _ type: String, _ method: String) -> [String] {
        [sequence(paths, type, method), activity(paths, type, method)]
    }

    /// A `Real<name>` with no `run`, which `Svc` names in `<name>`'s own directory.
    static func plain(_ name: String) -> EntryFile {
        ("\(name)/Alias.swift", "struct Real\(name) {}\ntypealias Svc = Real\(name)")
    }

    /// A `Real<name>` whose `run` calls `in<name>()`, which `Svc` names in `<name>`'s own directory.
    static func withRun(_ name: String) -> EntryFile {
        (
            "\(name)/Alias.swift",
            "struct Real\(name) { func run() { in\(name)() }\n    func in\(name)() {} }\ntypealias Svc = Real\(name)"
        )
    }
}

/// A typed entry has no file to rank from, so a name several declarations share comes to the first
/// of them, while a method in `extension Alias` is the type that extension's own directory means
/// (#78). `--entry Svc.run` then looked for `run` on a type that does not have it, and drew an
/// empty diagram with no word of why. An entry now means the first the name can come to with a
/// body for the method.
@Suite("An entry through a name several declarations share")
struct EntryThroughLaterDeclarationTests {

    private static let extensionInA: EntryFile = (
        "PkgA/Ext.swift", "extension Svc {\n    func run() { step() }\n    func step() {}\n}"
    )

    /// Each shape holds a `Svc` with no body for `run`, and `RealA`, which has one through
    /// `extension Svc`.
    private static let shapes: [[EntryFile]] = [
        // Two typealiases, the method through the later one.
        [
            ("PkgB/Alias.swift", "struct RealB {}\ntypealias Svc = RealB"),
            ("PkgA/Alias.swift", "struct RealA {}\ntypealias Svc = RealA"),
            extensionInA
        ],
        // A type of that name, which a typed name means first, beside the typealias.
        [
            ("PkgB/Svc.swift", "struct Svc {}"),
            ("PkgA/Alias.swift", "struct RealA {}\ntypealias Svc = RealA"),
            extensionInA
        ],
        // `private` typealiases, each named only in its own file.
        [
            ("PkgB/Alias.swift", "struct RealB {}\nprivate typealias Svc = RealB"),
            (
                "PkgA/Alias.swift",
                "struct RealA {}\nprivate typealias Svc = RealA\n"
                    + "extension Svc {\n    func run() { step() }\n    func step() {}\n}"
            )
        ],
        // A protocol of that name, which only requires the method.
        [
            ("PkgB/Svc.swift", "protocol Svc { func run() }"),
            ("PkgA/Alias.swift", "struct RealA {}\ntypealias Svc = RealA"),
            extensionInA
        ],
        // A typealias of a protocol that only requires it.
        [
            ("PkgB/Alias.swift", "protocol Proto { func run() }\ntypealias Svc = Proto"),
            ("PkgA/Alias.swift", "struct RealA {}\ntypealias Svc = RealA"),
            extensionInA
        ],
        // A local function of that name, which is no member of the type around it.
        [
            (
                "PkgB/Alias.swift",
                "struct RealB { func other() { func run() { inner() }\n    run() }\n    func inner() {} }\n"
                    + "typealias Svc = RealB"
            ),
            ("PkgA/Alias.swift", "struct RealA {}\ntypealias Svc = RealA"),
            extensionInA
        ]
    ]

    @Test("a sequence finds the method through a declaration read later, or read first",
          arguments: shapes, [false, true])
    func sequenceFindsIt(files: [EntryFile], reversed: Bool) throws {
        let (root, paths) = try EntryFixture.written(reversed ? files.reversed() : files)
        defer { try? FileManager.default.removeItem(at: root) }
        let text = EntryFixture.sequence(paths, "Svc", "run")
        #expect(text.contains("RealA->>RealA: step()"), "\(text)")
        #expect(text.contains("RealA.run"), "\(text)")
    }

    @Test("an activity diagram finds the method through a declaration read later, or read first",
          arguments: shapes, [false, true])
    func activityFindsIt(files: [EntryFile], reversed: Bool) throws {
        let (root, paths) = try EntryFixture.written(reversed ? files.reversed() : files)
        defer { try? FileManager.default.removeItem(at: root) }
        let text = EntryFixture.activity(paths, "Svc", "run")
        #expect(text.contains("step()"), "\(text)")
        #expect(text.contains("RealA.run"), "\(text)")
    }

    @Test("a dotted name is found the same way", arguments: [false, true])
    func dottedName(reversed: Bool) throws {
        let files: [EntryFile] = [
            ("PkgB/NS.swift", "struct RealB {}\nenum NS { typealias Svc = RealB }"),
            ("PkgA/NS.swift", "struct RealA {}\nenum NS { typealias Svc = RealA }"),
            ("PkgA/Ext.swift", "extension NS.Svc {\n    func run() { step() }\n    func step() {}\n}")
        ]
        let (root, paths) = try EntryFixture.written(reversed ? files.reversed() : files)
        defer { try? FileManager.default.removeItem(at: root) }
        let text = EntryFixture.sequence(paths, "NS.Svc", "run")
        #expect(text.contains("RealA->>RealA: step()"), "\(text)")
    }

    // MARK: - What stays as it was

    /// A method with no calls is still that type's method: a later type whose `run` makes calls
    /// must not take the entry over, so what counts is a body, not edges.
    @Test("the first with a body for the method is the one meant, though it makes no calls")
    func firstDeclaringWithNoCalls() throws {
        let (root, paths) = try EntryFixture.written([
            ("PkgB/Alias.swift", "struct RealB { func run() {} }\ntypealias Svc = RealB"),
            EntryFixture.withRun("A")
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        for text in EntryFixture.both(paths, "Svc", "run") {
            #expect(text.contains("RealB.run"), "\(text)")
            #expect(!text.contains("inA"), "\(text)")
        }
    }

    @Test("of several with a body for the method, the first read", arguments: [false, true])
    func severalDeclareIt(reversed: Bool) throws {
        let files = [EntryFixture.withRun("B"), EntryFixture.withRun("A")]
        let (root, paths) = try EntryFixture.written(reversed ? files.reversed() : files)
        defer { try? FileManager.default.removeItem(at: root) }
        for text in EntryFixture.both(paths, "Svc", "run") {
            #expect(text.contains(reversed ? "inA" : "inB"), "\(text)")
            #expect(!text.contains(reversed ? "inB" : "inA"), "\(text)")
        }
    }

    @Test("the one with a body is found wherever it is read among several", arguments: [
        ["B", "C", "A"], ["B", "A", "C"], ["A", "B", "C"], ["B", "C", "D", "A"], ["B", "A", "C", "D"]
    ])
    func oneAmongSeveral(order: [String]) throws {
        let (root, paths) = try EntryFixture.written(order.map {
            $0 == "A" ? EntryFixture.withRun($0) : EntryFixture.plain($0)
        })
        defer { try? FileManager.default.removeItem(at: root) }
        for text in EntryFixture.both(paths, "Svc", "run") {
            #expect(text.contains("inA"), "\(text)")
        }
    }

    @Test("of three, two with a body, the earlier one read")
    func orderOfThree() throws {
        let (root, paths) = try EntryFixture.written([
            EntryFixture.plain("B"), EntryFixture.withRun("C"), EntryFixture.withRun("A")
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        for text in EntryFixture.both(paths, "Svc", "run") {
            #expect(text.contains("inC"), "\(text)")
            #expect(!text.contains("inA"), "\(text)")
        }
    }

    /// `RealA`'s body is read first, but the typealias naming it last, so `RealB` comes first
    /// among the types and neither diagram goes by which body was read first.
    @Test("the order of the declarations decides, not the order of the bodies")
    func declarationOrderBeatsFileOrder() throws {
        let (root, paths) = try EntryFixture.written([
            ("Impl/RealA.swift", "struct RealA { func run() { inA() }\n    func inA() {} }"),
            EntryFixture.withRun("B"),
            ("A/Alias.swift", "typealias Svc = RealA")
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        for text in EntryFixture.both(paths, "Svc", "run") {
            #expect(text.contains("inB"), "\(text)")
            #expect(!text.contains("inA"), "\(text)")
        }
    }

    @Test("a type of that name before a typealias, when both have a body", arguments: [false, true])
    func typeBeforeTypealias(reversed: Bool) throws {
        let files: [EntryFile] = [
            EntryFixture.withRun("A"),
            ("T/Svc.swift", "struct Svc { func run() { inType() }\n    func inType() {} }")
        ]
        let (root, paths) = try EntryFixture.written(reversed ? files.reversed() : files)
        defer { try? FileManager.default.removeItem(at: root) }
        for text in EntryFixture.both(paths, "Svc", "run") {
            #expect(text.contains("inType"), "\(text)")
            #expect(!text.contains("inA"), "\(text)")
        }
    }

    @Test("a method none has a body for is the first's, and draws nothing")
    func noneDeclaresIt() throws {
        let (root, paths) = try EntryFixture.written(Self.shapes[0])
        defer { try? FileManager.default.removeItem(at: root) }
        for text in EntryFixture.both(paths, "Svc", "missing") {
            #expect(text.contains("RealB.missing"), "\(text)")
            #expect(!text.contains("step"), "\(text)")
        }
    }

    @Test("the aliased type's own name still reaches the method")
    func aliasedTypeName() throws {
        let (root, paths) = try EntryFixture.written(Self.shapes[0])
        defer { try? FileManager.default.removeItem(at: root) }
        let text = EntryFixture.sequence(paths, "RealA", "run")
        #expect(text.contains("RealA->>RealA: step()"), "\(text)")
    }

    @Test("what a name can come to starts with what it comes to with no file, and ends with itself")
    func entryTypesOrder() throws {
        let resolver = TypeAliasResolver(items: try [
            ("/r/B/Alias.swift", "typealias Svc = RealB"),
            ("/r/A/Alias.swift", "typealias Svc = RealA"),
            ("/r/C/Alias.swift", "typealias Svc = RealA")
        ].flatMap { path, source in
            try #require(
                SyntaxStructure.declarations(in: source, file: URL(fileURLWithPath: path))?.substructure
            )
        })
        #expect(resolver.entryTypes(of: "Svc") == ["RealB", "RealA", "Svc"])
        #expect(resolver.entryTypes(of: "Plain") == ["Plain"])
        #expect(TypeAliasResolver.withoutProject.entryTypes(of: "Svc") == ["Svc"])
    }
}
