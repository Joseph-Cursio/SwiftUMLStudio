import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

/// Several bodies can be filed under one `Type.method`: overloads, same-named types, and a
/// function or type local to a body. The sequence diagram drew every one and the activity diagram
/// the first it met, so the two drew different code for one entry, and either could draw a body
/// Swift cannot reach by that name (#235). Each case here was checked against what `swiftc` runs.
@Suite("One body for an entry")
struct OneEntryBodyTests {
    /// Both diagrams of `type.method` over `files`, written in that order.
    private static func both(_ files: [EntryFile], _ type: String, _ method: String) throws -> [String] {
        let (root, paths) = try EntryFixture.written(files)
        defer { try? FileManager.default.removeItem(at: root) }
        return EntryFixture.both(paths, type, method)
    }

    @Test("of two overloads, both draw the first written", arguments: [false, true])
    func overloads(reversed: Bool) throws {
        let first = "    func run() { first() }\n", second = "    func run(_ value: Int) { second() }\n"
        let source = "struct Over {\n" + (reversed ? second + first : first + second)
            + "    func first() {}\n    func second() {}\n}\n"
        for text in try Self.both([("Pkg/Over.swift", source)], "Over", "run") {
            #expect(text.contains(reversed ? "second()" : "first()"), "\(text)")
            #expect(!text.contains(reversed ? "first()" : "second()"), "\(text)")
        }
    }

    @Test("of same-named nested types, both draw the first read")
    func sameNamedTypes() throws {
        let source = "enum First { struct Real { func run() { fromFirst() }; func fromFirst() {} } }\n"
            + "enum Second { struct Real { func run() { fromSecond() }; func fromSecond() {} } }\n"
        for text in try Self.both([("Pkg/Two.swift", source)], "Real", "run") {
            #expect(text.contains("fromFirst()"), "\(text)")
            #expect(!text.contains("fromSecond"), "\(text)")
        }
    }

    @Test("a top-level type is meant before a nested one of its name read first")
    func topLevelBeforeNested() throws {
        let files: [EntryFile] = [
            ("PkgA/Nested.swift", "enum First { struct Real { func run() { fromNested() }; func fromNested() {} } }"),
            ("PkgB/Real.swift", "struct Real { func run() { fromTop() }\n    func fromTop() {} }"),
        ]
        for text in try Self.both(files, "Real", "run") {
            #expect(text.contains("fromTop()"), "\(text)")
            #expect(!text.contains("fromNested"), "\(text)")
        }
    }

    private static let realBody = "struct Real {\n    func run() { fromNamed() }\n    func fromNamed() {}\n}\n"

    /// `Real().run()` runs the top-level `Real`'s, whichever is written first.
    @Test("a type local to a body is not drawn for the type of that name",
          arguments: ["init()", "func make()"], [false, true])
    func localType(holder: String, hostFirst: Bool) throws {
        let host = "struct Host {\n    \(holder) {\n        struct Real {\n            func run() { fromLocal() }\n"
            + "            func fromLocal() {}\n        }\n    }\n}\n"
        let source = hostFirst ? host + Self.realBody : Self.realBody + host
        for text in try Self.both([("Pkg/All.swift", source)], "Real", "run") {
            #expect(text.contains("fromNamed()"), "\(text)")
            #expect(!text.contains("fromLocal"), "\(text)")
        }
    }

    @Test("a type local to a body, with no other of its name, is not offered and draws nothing")
    func localTypeAlone() throws {
        let source = "struct Host {\n    init() {\n        struct Real {\n            func run() { fromLocal() }\n"
            + "            func fromLocal() {}\n        }\n    }\n}\n"
        let (root, paths) = try EntryFixture.written([("Pkg/Host.swift", source)])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(!SequenceDiagramGenerator().findEntryPoints(for: paths).contains("Real.run"))
        for text in EntryFixture.both(paths, "Real", "run") {
            #expect(!text.contains("fromLocal"), "\(text)")
        }
    }

    @Test("a call inside a local type's member reaches that type's members")
    func callInsideLocalType() throws {
        let source = "struct Host {\n    func make() {\n        struct Real {\n            func run() { fromLocal() }\n"
            + "            func fromLocal() { deeper() }\n            func deeper() {}\n        }\n"
            + "        Real().run()\n    }\n}\n" + Self.realBody
        let (root, paths) = try EntryFixture.written([("Pkg/All.swift", source)])
        defer { try? FileManager.default.removeItem(at: root) }
        let text = EntryFixture.sequence(paths, "Host", "make")
        #expect(text.contains("fromLocal()") && text.contains("deeper()"), "\(text)")
        #expect(!text.contains("fromNamed"), "\(text)")
    }

    private static let realB = "struct RealB {\n    func outer() {\n        func run() { inner() }\n        run()\n"
        + "    }\n    func inner() {}\n}\n"

    @Test("a function local to a method is no member: neither diagram draws it")
    func localFunction() throws {
        for text in try Self.both([("Pkg/RealB.swift", Self.realB)], "RealB", "run") {
            #expect(!text.contains("inner()"), "\(text)")
        }
    }

    @Test("nor through a typealias")
    func localFunctionThroughAlias() throws {
        let files: [EntryFile] = [("Pkg/RealB.swift", Self.realB), ("Pkg/Alias.swift", "typealias Svc = RealB\n")]
        for text in try Self.both(files, "Svc", "run") {
            #expect(!text.contains("inner()"), "\(text)")
        }
    }

    @Test("the method holding a local function still reaches its calls")
    func localFunctionFromItsHolder() throws {
        let (root, paths) = try EntryFixture.written([("Pkg/RealB.swift", Self.realB)])
        defer { try? FileManager.default.removeItem(at: root) }
        let text = EntryFixture.sequence(paths, "RealB", "outer")
        #expect(text.contains("run()") && text.contains("inner()"), "\(text)")
    }

    private static let bothSource = "struct Both {\n    func run() { fromMember() }\n    func fromMember() {}\n"
        + "    func outer() {\n        func run() { fromLocal() }\n        run()\n    }\n    func fromLocal() {}\n}\n"

    @Test("beside a member of its name, the member is the entry")
    func localFunctionBesideMember() throws {
        for text in try Self.both([("Pkg/Both.swift", Self.bothSource)], "Both", "run") {
            #expect(text.contains("fromMember()"), "\(text)")
            #expect(!text.contains("fromLocal"), "\(text)")
        }
    }

    /// `Both().outer()` runs the local `run`, which Swift finds before the member.
    @Test("a bare call reaches the local function, not the member of its name")
    func bareCallReachesLocalFunction() throws {
        let (root, paths) = try EntryFixture.written([("Pkg/Both.swift", Self.bothSource)])
        defer { try? FileManager.default.removeItem(at: root) }
        let text = EntryFixture.sequence(paths, "Both", "outer")
        #expect(text.contains("fromLocal()"), "\(text)")
        #expect(!text.contains("fromMember"), "\(text)")
    }

    /// `Service().start()` reaches only the `load` with no arguments.
    @Test("a call reaches the overload its argument labels fit", arguments: [
        ("load()", "fromPlain()", "fromKeyed"), ("load(\"key\")", "fromKeyed()", "fromPlain"),
        ("self.load(key: \"key\")", "fromLabeled()", "fromPlain"),
    ])
    func overloadByLabels(call: String, reached: String, passed: String) throws {
        let source = "struct Service {\n    func start() { \(call) }\n    func load() { fromPlain() }\n"
            + "    func load(_ key: String) { fromKeyed() }\n    func load(key: String) { fromLabeled() }\n"
            + "    func fromPlain() {}\n    func fromKeyed() {}\n    func fromLabeled() {}\n}\n"
        let (root, paths) = try EntryFixture.written([("Pkg/Service.swift", source)])
        defer { try? FileManager.default.removeItem(at: root) }
        let text = EntryFixture.sequence(paths, "Service", "start")
        #expect(text.contains(reached), "\(text)")
        #expect(!text.contains(passed), "\(text)")
    }

    @Test("a call whose labels fit no overload, or are not known, still reaches each", arguments: [
        "load(1, 2)", "load { }"
    ])
    func unmatchedCallReachesEach(call: String) throws {
        let source = "struct Service {\n    func start() { \(call) }\n    func load() { fromPlain() }\n"
            + "    func load(_ key: String) { fromKeyed() }\n    func fromPlain() {}\n    func fromKeyed() {}\n}\n"
        let (root, paths) = try EntryFixture.written([("Pkg/Service.swift", source)])
        defer { try? FileManager.default.removeItem(at: root) }
        let text = EntryFixture.sequence(paths, "Service", "start")
        #expect(text.contains("fromPlain()") && text.contains("fromKeyed()"), "\(text)")
    }

    private static func parameter(_ label: String, defaulted: Bool = false, variadic: Bool = false) -> CallParameter {
        CallParameter(label: label, hasDefault: defaulted, isVariadic: variadic)
    }

    @Test("a parameter with a default may be left out, and a variadic one takes any number")
    func labelMatching() {
        let defaulted = [Self.parameter("_"), Self.parameter("retry", defaulted: true), Self.parameter("by")]
        #expect(CallParameter.accepts(defaulted, labels: ["_", "by"]))
        #expect(CallParameter.accepts(defaulted, labels: ["_", "retry", "by"]))
        #expect(!CallParameter.accepts(defaulted, labels: ["_", "retry"]))
        #expect(!CallParameter.accepts(defaulted, labels: ["by", "_"]))
        let variadic = [Self.parameter("values", variadic: true), Self.parameter("sep", defaulted: true)]
        #expect(CallParameter.accepts(variadic, labels: []))
        #expect(CallParameter.accepts(variadic, labels: ["values", "_", "_", "sep"]))
        #expect(!CallParameter.accepts(variadic, labels: ["_"]))
    }

    @Test("a call through self reaches the member, not the local function")
    func selfCallReachesMember() throws {
        let source = Self.bothSource.replacingOccurrences(of: "        run()\n", with: "        self.run()\n")
        let (root, paths) = try EntryFixture.written([("Pkg/Both.swift", source)])
        defer { try? FileManager.default.removeItem(at: root) }
        let text = EntryFixture.sequence(paths, "Both", "outer")
        #expect(text.contains("fromMember()"), "\(text)")
        #expect(!text.contains("fromLocal"), "\(text)")
    }
}
