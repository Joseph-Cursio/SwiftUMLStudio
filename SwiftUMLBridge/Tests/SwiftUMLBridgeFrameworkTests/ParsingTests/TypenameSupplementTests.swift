import SwiftParser
import SwiftSyntax
import Testing
@testable import SwiftUMLBridgeFramework

/// In `var a, b: Int` the syntax gives only `b` a type annotation, and SourceKit's structure gives
/// both names the shared type. `a`'s type came from the SourceKit typename supplement until the
/// builder learned to read the shared annotation itself (#146), so the first test now passes with
/// or without the supplement. The second checks that the supplement keys each type by the UTF-8
/// offset of the name, which is how the builder looks it up. Emptying its map once passed the
/// whole suite (#71).
@Suite("The SourceKit typename supplement")
struct TypenameSupplementTests {

    @Test("names that share one annotation all get its type, in nested types and classes too")
    func sharedAnnotation() {
        let text = ClassDiagramGenerator().generateScript(for: """
            struct S {
                var a, b: Int
                struct Inner { let e, f: Double }
            }
            final class C {
                var g, h: Bool
                init() { g = true; h = true }
            }
            """, with: Configuration(format: .plantuml)).text
        #expect(text.contains("~a : Int"), "\(text)")
        #expect(text.contains("~e : Double"), "\(text)")
        #expect(text.contains("~g : Bool"), "\(text)")
    }

    /// The builder looks a variable up by the offset SwiftSyntax gives its name, so every name
    /// SourceKit types must be stored at that offset: after a byte-order mark, multi-byte text and
    /// CRLF line ends, in backticks, and in a type nested in an extension.
    @Test("the supplement stores each type at the offset SwiftSyntax gives the name", arguments: [
        "\u{FEFF}// caf\u{E9} \u{1F600} \u{4E2D}\u{6587}\r\nlet s = \"\u{1F600}\"\r\n"
            + "struct S {\r\n    var a, b: Int\r\n}\r\n",
        "struct Option {\n    var `default`, fallback: Int\n}\n",
        "struct Point {}\nextension Point {\n    struct Delta { var dx, dy: Int }\n}\n"
    ])
    func keysAreNameOffsets(source: String) {
        let map = SyntaxStructure.buildTypenameMap(from: source, sdkPath: nil)
        let names = Parser.parse(source: source).tokens(viewMode: .sourceAccurate)
            .filter { $0.parent?.is(IdentifierPatternSyntax.self) == true && $0.text != "s" }
        #expect(names.count == 2)
        for name in names {
            #expect(map[name.positionAfterSkippingLeadingTrivia.utf8Offset] == "Int", "\(name.text) in \(map)")
        }
    }
}
