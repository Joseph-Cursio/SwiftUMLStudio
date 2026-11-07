import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// A dotted name's first component that is a typealias of a type outside the diagram starts the
/// name at that type: after `typealias Array = Date`, `Array.V` is `Date.V`. The lookup knew only
/// that the start was some outside type, so it searched the name as written and took the `V` of
/// `extension [Int]`, a member of Swift's `Array`, or, with none, drew an undeclared `Array.V`
/// (#247). Each case builds with swiftc, which makes each writer conform to the protocol expected.
@Suite("A typealias of a type outside the diagram starts a dotted name at that type")
struct AliasOfOutsideTypeStartTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let files: [String]
        /// The PlantUML supertype lines, in any order.
        let expected: [String]

        var testDescription: String { name }
    }

    private static let protocols = """
        import Foundation
        protocol P1 {}
        protocol P2 {}
        protocol P3 {}
        """

    private static let members = protocols + """

        extension [Int] { typealias V = P1 }
        extension Date { typealias V = P2 }
        extension Data { typealias V = P3 }
        """

    static let cases: [Case] = [
        Case(name: "the issue's reproduction", files: [
            members, "import Foundation\nenum E { typealias Array = Date; struct W: Array.V {} }"
        ], expected: ["P2 <|.. E.W : conforms to"]),
        Case(name: "the alias at file scope", files: [
            members, "import Foundation\ntypealias Array = Date\nstruct W: Array.V {}"
        ], expected: ["P2 <|.. W : conforms to"]),
        Case(name: "two enclosing types, each with its own alias", files: [
            members, """
                import Foundation
                enum E { typealias Array = Date; struct W1: Array.V {} }
                enum F { typealias Array = Data; struct W2: Array.V {} }
                """
        ], expected: ["P2 <|.. E.W1 : conforms to", "P3 <|.. F.W2 : conforms to"]),
        Case(name: "two enclosing types, with no member recorded under the name as written", files: [
            protocols + "\nextension Date { typealias V = P2 }\nextension Data { typealias V = P3 }", """
                import Foundation
                enum E { typealias Array = Date; struct W1: Array.V {} }
                enum F { typealias Array = Data; struct W2: Array.V {} }
                """
        ], expected: ["P2 <|.. E.W1 : conforms to", "P3 <|.. F.W2 : conforms to"]),
        Case(name: "an alias of sugar", files: [
            members, "enum E2 { typealias Arr = [Int]; struct W2: Arr.V {} }"
        ], expected: ["P1 <|.. E2.W2 : conforms to"]),
        Case(name: "a chain of aliases", files: [
            members, "import Foundation\ntypealias D = Date\nenum E { typealias Array = D; struct W: Array.V {} }"
        ], expected: ["P2 <|.. E.W : conforms to"]),
        Case(name: "control: the outside type itself", files: [
            members, "struct W0: Array.V {}"
        ], expected: ["P1 <|.. W0 : conforms to"])
    ]

    /// Each case is read with its files in the order given and reversed, so no answer comes from
    /// which file is read first.
    @Test("the name means the aliased type's member", arguments: cases, [false, true])
    func meansTheAliasedTypesMember(_ testCase: Case, reversed: Bool) throws {
        let given = testCase.files.map { (module: Optional("App"), source: $0) }
        let items = try moduleQualifiedItems(reversed ? given.reversed() : given)
        let text = DiagramScript(items: items, configuration: Configuration(format: .plantuml)).text
        let lines = ClassDiagramIds.lines(of: text, containing: "<|")
        #expect(Set(lines) == Set(testCase.expected))
        #expect(lines.count == testCase.expected.count)
    }
}
