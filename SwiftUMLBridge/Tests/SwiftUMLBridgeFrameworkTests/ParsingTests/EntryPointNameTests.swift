@testable import SwiftUMLBridgeFramework
import Testing

/// `EntryPointName` reads what the CLI's `--entry` and the Studio's entry field are given.
@Suite("EntryPointName")
struct EntryPointNameTests {
    @Test("the method is what follows the last dot, the type all before it", arguments: [
        ("Loader.load", "Loader", "load"),
        ("NS.Real.run", "NS.Real", "run"),
        ("A.B.C.go", "A.B.C", "go"),
        ("`Plain`.helper", "`Plain`", "helper"),
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
