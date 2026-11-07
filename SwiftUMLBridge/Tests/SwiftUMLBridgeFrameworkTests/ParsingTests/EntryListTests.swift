import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// The Studio's entry list, `findEntryPoints(for:)`, offered names that could not draw (#234): a
/// method in `extension NS.Real` is listed as `NS.Real.run`, which both the CLI and the Studio
/// refused as more than two parts, and a function local to a body or a protocol requirement was
/// listed as a member, with nothing to draw. Every name listed now draws its method.
@Suite("Every entry listed draws its method")
struct EntryListTests {
    private static let nested = """
        enum NS { struct Real {} }
        extension NS.Real {
            func run() { helper() }
            func helper() {}
        }
        """

    private func entries(_ files: [EntryFile]) throws -> [String] {
        let (root, paths) = try EntryFixture.written(files)
        defer { try? FileManager.default.removeItem(at: root) }
        return SequenceDiagramGenerator().findEntryPoints(for: paths)
    }

    // MARK: - What the list offers

    @Test("a function local to a body and a protocol requirement are not listed, members are")
    func listsOnlyMembersWithBodies() throws {
        let listed = try entries([
            ("Pkg/Host.swift", """
                struct Host {
                    init() {
                        func setup() { work() }
                        setup()
                    }
                    func work() {}
                }
                protocol Runs { func go() }
                extension Runs { func went() {} }
                """)
        ])
        #expect(listed == ["Host.work", "Runs.went"])
    }

    @Test("the list and the activity list agree")
    func activityListAgrees() throws {
        let (root, paths) = try EntryFixture.written([("Pkg/Real.swift", Self.nested)])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(ActivityDiagramGenerator().findEntryPoints(for: paths)
            == SequenceDiagramGenerator().findEntryPoints(for: paths))
    }

    // MARK: - Each name listed draws

    @Test("a method of an extension of a nested type is listed by its whole name, and that name draws it")
    func nestedExtensionDraws() throws {
        let (root, paths) = try EntryFixture.written([("Pkg/Real.swift", Self.nested)])
        defer { try? FileManager.default.removeItem(at: root) }
        let listed = SequenceDiagramGenerator().findEntryPoints(for: paths)
        #expect(listed == ["NS.Real.helper", "NS.Real.run"])
        let name = try #require(EntryPointName("NS.Real.run"))
        for text in EntryFixture.both(paths, name.type, name.method) {
            #expect(text.contains("helper()"), "\(text)")
        }
    }

    /// The list names it `Inner.run`, as its calls are filed, but the whole name is what Swift
    /// writes outside `Outer`, and typing it once drew an empty diagram.
    @Test("a method of a type nested inline draws by its whole name too")
    func inlineNestedWholeNameDraws() throws {
        let (root, paths) = try EntryFixture.written([
            ("Pkg/Outer.swift", "enum Outer { struct Inner { func run() { helper() }\n    func helper() {} } }")
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        for text in EntryFixture.both(paths, "Outer.Inner", "run") {
            #expect(text.contains("helper()"), "\(text)")
        }
    }

    /// A dotted name that no nested type has the method under is still the type as typed, so a
    /// local function's calls are filed there as before.
    @Test("a dotted name nothing is filed under stays the type as typed")
    func unknownDottedNameKeepsItsType() throws {
        let (root, paths) = try EntryFixture.written([("Pkg/Real.swift", Self.nested)])
        defer { try? FileManager.default.removeItem(at: root) }
        let text = EntryFixture.sequence(paths, "MyModule.Loader", "load")
        #expect(text.contains("MyModule.Loader"), "\(text)")
    }
}

/// `EntryPointName` reads what the CLI's `--entry` and the Studio's entry field are given.
@Suite("EntryPointName")
struct EntryPointNameTests {
    @Test("the method is what follows the last dot, the type all before it", arguments: [
        ("Loader.load", "Loader", "load"),
        ("NS.Real.run", "NS.Real", "run"),
        ("A.B.C.go", "A.B.C", "go"),
        ("`Plain`.helper", "`Plain`", "helper")
    ])
    func splitsAtLastDot(written: String, type: String, method: String) throws {
        let name = try #require(EntryPointName(written))
        #expect(name.type == type)
        #expect(name.method == method)
    }

    @Test("a name with no dot, or a part left empty, is none", arguments: [
        "", "Loader", "Loader.", ".load", ".", "..", "Loader..load", "NS..Real.run"
    ])
    func rejects(written: String) {
        #expect(EntryPointName(written) == nil)
    }
}
