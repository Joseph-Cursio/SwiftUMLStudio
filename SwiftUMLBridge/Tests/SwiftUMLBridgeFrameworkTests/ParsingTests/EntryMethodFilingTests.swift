import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

/// A method is filed under a name the entry's own declarations may not lead to: a nested type's
/// under its innermost name, and one in `extension Name` under whatever `Name` means in that file,
/// which may be no declaration of it at all. Each of these drew an empty diagram, or another
/// type's, with no word of why.
@Suite("An entry to a method filed under another name")
struct EntryMethodFilingTests {

    private static let nestedBody = "enum OB { struct IB { func run() { inIB() }\n    func inIB() {} } }\n"

    @Test("a typealias of a nested type reaches a method in that type's body")
    func aliasOfNestedType() throws {
        let (root, paths) = try EntryFixture.written([
            ("Pkg/Alias.swift", Self.nestedBody + "typealias Svc = OB.IB")
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        for text in EntryFixture.both(paths, "Svc", "run") {
            #expect(text.contains("IB.run"), "\(text)")
            #expect(text.contains("inIB()"), "\(text)")
        }
    }

    @Test("a nested type's body is not passed over for a later type's")
    func nestedTypeReadFirst() throws {
        let (root, paths) = try EntryFixture.written([
            ("PkgB/Alias.swift", Self.nestedBody + "typealias Svc = OB.IB"),
            EntryFixture.withRun("A"),
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        for text in EntryFixture.both(paths, "Svc", "run") {
            #expect(text.contains("inIB()"), "\(text)")
            #expect(!text.contains("inA"), "\(text)")
        }
    }

    @Test("a nested type's body is found after a type with none")
    func nestedTypeReadLater() throws {
        let (root, paths) = try EntryFixture.written([
            EntryFixture.plain("C"),
            ("PkgB/Alias.swift", Self.nestedBody + "typealias Svc = OB.IB"),
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        for text in EntryFixture.both(paths, "Svc", "run") {
            #expect(text.contains("inIB()"), "\(text)")
        }
    }

    /// Filed under `IB`, as `OC.IB`'s `run` is, but only `OB.IB` is what the typealias names.
    @Test("a nested type of the same innermost name, inside another type, is not meant")
    func otherNestingOfTheName() throws {
        let (root, paths) = try EntryFixture.written([
            (
                "Pkg/Types.swift",
                "enum OB { struct IB {} }\nenum OC { struct IB { func run() { inOC() }\n    func inOC() {} } }\n"
                    + "typealias Svc = OB.IB"
            ),
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        for text in EntryFixture.both(paths, "Svc", "run") {
            #expect(text.contains("OB.IB.run"), "\(text)")
            #expect(!text.contains("inOC"), "\(text)")
        }
    }

    /// `Date` in the extension's file cannot see the `private` typealias, so the method is filed
    /// under `Date`, which is what the entry list offers.
    @Test("a method filed under the typed name, when no declaration of it is visible there")
    func privateTypealiasElsewhere() throws {
        let (root, paths) = try EntryFixture.written([
            ("PkgB/Alias.swift", "struct MyDate {}\nprivate typealias Date = MyDate"),
            ("PkgA/Ext.swift", "import Foundation\nextension Date {\n    func run() { step() }\n    func step() {}\n}"),
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(SequenceDiagramGenerator().findEntryPoints(for: paths).contains("Date.run"))
        for text in EntryFixture.both(paths, "Date", "run") {
            #expect(text.contains("Date.run"), "\(text)")
            #expect(text.contains("step()"), "\(text)")
        }
    }

    /// One file holds both, so what the file itself makes the name is the `private` one, which the
    /// extension cannot see. Each declaration is followed for what it comes to.
    @Test("a declaration its own file's first typealias hides is still followed")
    func twoClausesOfOneFile() throws {
        let (root, paths) = try EntryFixture.written([
            (
                "PkgB/Alias.swift",
                "struct RealA {}\nstruct RealB {}\n#if os(iOS)\nprivate typealias Svc = RealB\n"
                    + "#else\ntypealias Svc = RealA\n#endif"
            ),
            ("PkgC/Ext.swift", "extension Svc {\n    func run() { step() }\n    func step() {}\n}"),
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        for text in EntryFixture.both(paths, "Svc", "run") {
            #expect(text.contains("RealA.run"), "\(text)")
            #expect(text.contains("step()"), "\(text)")
        }
    }

    @Test("every entry the list offers beside a typealias of that name draws", arguments: ["run", "step"])
    func listedNestedType(method: String) throws {
        let (root, paths) = try EntryFixture.written([
            (
                "PkgA/Config.swift",
                "enum Config { struct Logger { func run() { step() }\n    func step() { last() }\n"
                    + "    func last() {} } }"
            ),
            ("PkgB/Alias.swift", "struct Lumber {}\ntypealias Logger = Lumber"),
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(SequenceDiagramGenerator().findEntryPoints(for: paths).contains("Logger.\(method)"))
        for text in EntryFixture.both(paths, "Logger", method) {
            #expect(text.contains("Logger.\(method)"), "\(text)")
            #expect(text.contains(method == "run" ? "step()" : "last()"), "\(text)")
        }
    }

    /// A top-level `Config` is the typealias, as Swift reads it, so the alias's type comes first.
    @Test("the typealias's type is meant before a nested type of its name")
    func aliasBeforeNestedName() throws {
        let (root, paths) = try EntryFixture.written([
            (
                "PkgB/Config.swift",
                "enum Outer { struct Config { func load() { inNested() }\n    func inNested() {} } }"
            ),
            (
                "PkgA/Alias.swift",
                "struct AppConfig { func load() { inAlias() }\n    func inAlias() {} }\ntypealias Config = AppConfig"
            ),
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        for text in EntryFixture.both(paths, "Config", "load") {
            #expect(text.contains("inAlias"), "\(text)")
            #expect(!text.contains("inNested"), "\(text)")
        }
    }

    @Test("a requirement alone is still that protocol's, and draws nothing", arguments: [false, true])
    func requirementAlone(viaAlias: Bool) throws {
        let (root, paths) = try EntryFixture.written([
            ("Pkg/Proto.swift", "protocol Proto { func run() }\n" + (viaAlias ? "typealias Svc = Proto" : ""))
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        for text in EntryFixture.both(paths, viaAlias ? "Svc" : "Proto", "run") {
            #expect(text.contains("Proto.run"), "\(text)")
        }
    }

    private static let extensionOfSvc = "extension Svc {\n    func run() { step() }\n    func step() {}\n}"

    @Test("a typealias of a typealias is followed to the type")
    func aliasOfAlias() throws {
        let (root, paths) = try EntryFixture.written([
            EntryFixture.plain("B"),
            ("PkgA/Alias.swift", "struct RealA {}\ntypealias Mid = RealA\ntypealias Svc = Mid"),
            ("PkgA/Ext.swift", Self.extensionOfSvc),
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        for text in EntryFixture.both(paths, "Svc", "run") {
            #expect(text.contains("RealA.run"), "\(text)")
            #expect(text.contains("step()"), "\(text)")
        }
    }

    /// `[Int]` is the standard library's `Array`, whatever the project calls `Array` (#126).
    @Test("a typealias of sugar is the standard library's type, as its extension is")
    func aliasOfSugar() throws {
        let (root, paths) = try EntryFixture.written([
            EntryFixture.plain("B"),
            ("PkgA/Alias.swift", "typealias Svc = [Int]\n" + Self.extensionOfSvc),
            ("PkgC/Array.swift", "struct Other {}\ntypealias Array = Other"),
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        for text in EntryFixture.both(paths, "Svc", "run") {
            #expect(text.contains("Array.run"), "\(text)")
            #expect(text.contains("step()"), "\(text)")
        }
    }

    /// `Inner` here is the one beside the typealias, so its target is read where it is written.
    @Test("a typealias's target is read from where the typealias is written")
    func targetBesideAlias() throws {
        let (root, paths) = try EntryFixture.written([
            ("PkgB/NS.swift", "struct RealB {}\nenum NS { typealias Svc = RealB }"),
            ("PkgA/NS.swift", "enum NS { struct Inner {}\n    typealias Svc = Inner }"),
            ("PkgA/Ext.swift", "extension NS.Svc {\n    func run() { step() }\n    func step() {}\n}"),
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        for text in EntryFixture.both(paths, "NS.Svc", "run") {
            #expect(text.contains("NS.Inner.run"), "\(text)")
            #expect(text.contains("step()"), "\(text)")
        }
    }

    /// `run(_:)` in the body and `run()` in the extension are overloads, which Swift allows.
    private static let nestedBodyAndExtension: [EntryFile] = [
        ("Pkg/Nested.swift", "enum OB { struct IB { func run(_ value: Int) { inBody() }\n    func inBody() {} } }"),
        ("Pkg/Ext.swift", "extension OB.IB { func run() { inExt() }\n    func inExt() {} }\ntypealias Svc = OB.IB"),
    ]

    @Test("what is filed under the typealias's spelling wins, whichever file is read first", arguments: [false, true])
    func extensionBeforeNestedSpelling(reversed: Bool) throws {
        let files = Self.nestedBodyAndExtension
        let (root, paths) = try EntryFixture.written(reversed ? files.reversed() : files)
        defer { try? FileManager.default.removeItem(at: root) }
        for text in EntryFixture.both(paths, "Svc", "run") {
            #expect(text.contains("OB.IB.run"), "\(text)")
            #expect(text.contains("inExt()"), "\(text)")
        }
    }

    @Test("a nested namesake read first takes nothing from the extension the typealias means")
    func namesakeBeforeExtension() throws {
        let (root, paths) = try EntryFixture.written(
            [("Pkg/Other.swift", "enum OC { struct IB { func run() { inOC() }\n    func inOC() {} } }")]
                + Self.nestedBodyAndExtension
        )
        defer { try? FileManager.default.removeItem(at: root) }
        for text in EntryFixture.both(paths, "Svc", "run") {
            #expect(text.contains("inExt()"), "\(text)")
            #expect(!text.contains("inOC"), "\(text)")
        }
    }

    private static let topLevelBesideNamesake: EntryFile = (
        "PkgB/Alias.swift",
        "struct IB {}\nenum OC { struct IB { func run() { inOC() }\n    func inOC() {} } }\ntypealias Svc = IB"
    )

    /// `Svc` here is the top-level `IB`, which has no `run`, as Swift says of `Svc().run()`.
    @Test("a typealias of a top-level type is not met by a nested type of that name")
    func undottedTargetIsTopLevel() throws {
        let (root, paths) = try EntryFixture.written([Self.topLevelBesideNamesake, EntryFixture.withRun("C")])
        defer { try? FileManager.default.removeItem(at: root) }
        for text in EntryFixture.both(paths, "Svc", "run") {
            #expect(text.contains("inC()"), "\(text)")
            #expect(!text.contains("inOC"), "\(text)")
        }
    }

    @Test("with no other declaration, that typealias draws nothing rather than the namesake's body")
    func undottedTargetAlone() throws {
        let (root, paths) = try EntryFixture.written([Self.topLevelBesideNamesake])
        defer { try? FileManager.default.removeItem(at: root) }
        for text in EntryFixture.both(paths, "Svc", "run") {
            #expect(text.contains("IB.run"), "\(text)")
            #expect(!text.contains("inOC"), "\(text)")
        }
    }
}
