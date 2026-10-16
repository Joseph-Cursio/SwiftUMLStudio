import Testing
@testable import SwiftUMLBridgeFramework

/// In `var a, b: Int` the syntax gives only `b` a type annotation, and SourceKit's structure gives
/// both names the shared type. So `a`'s type comes from the SourceKit typename supplement, which
/// keys each variable by the types it is nested in. No other test reads the supplement: emptying
/// its map passed the whole suite (#71).
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
}
