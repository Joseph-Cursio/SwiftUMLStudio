@testable import SwiftUMLBridgeFramework
import Testing

@Suite("TypeSyntax.names(_:bareOrIn:)")
struct FrameworkTypeNameTests {

    @Test("a framework's name matches bare or with its own module, however that is spelt", arguments: [
        ("Model", true),
        ("SwiftData.Model", true),
        ("`SwiftData`.`Model`", true),
        ("SwiftData . Model", true),
        ("`Model`", true),
        ("MyKit.Model", false),
        ("Outer.SwiftData.Model", false),
        ("SwiftData<Int>.Model", false),
        ("`SwiftData.Model`", false),
        ("Models", false),
        ("SwiftData", false),
        ("[Model]", false),
    ])
    func matches(spelling: String, expected: Bool) throws {
        #expect(try extendedType(spelling).names("Model", bareOrIn: "SwiftData") == expected)
    }
}
