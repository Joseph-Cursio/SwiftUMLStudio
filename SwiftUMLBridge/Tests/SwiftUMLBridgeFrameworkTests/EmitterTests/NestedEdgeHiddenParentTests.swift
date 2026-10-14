import Testing
@testable import SwiftUMLBridgeFramework

/// A nested type's edge names a parent the diagram does not draw by its qualified name, so it
/// never hangs off a drawn type that shares the parent's short name (#67).
@Suite("Nested-type edges whose parent is not drawn")
struct NestedEdgeHiddenParentTests {

    private func edges(
        of source: String, _ format: DiagramFormat = .plantuml, elements: ElementOptions = ElementOptions()
    ) -> [String] {
        let marker = format == .plantuml ? "+--" : "+-"
        return ClassDiagramIds.lines(of: ClassDiagramIds.script(for: source, format: format, elements: elements),
                                     containing: marker)
    }

    // MARK: - Hidden Type Parents

    @Test("a type nested in a hidden type does not hang off a drawn type with the hidden type's short name")
    func hiddenParentDoesNotBorrowDrawnType() {
        let source = "struct Outer { fileprivate struct Foo { struct Inner {} } }\nstruct Foo {}"
        #expect(edges(of: source) == ["Outer.Foo +-- Outer.Foo.Inner"])
        #expect(edges(of: source, .nomnoml) == ["[Outer.Foo] +- [Outer.Foo.Inner]"])
    }

    @Test("nor off an extension's alias that is the hidden type's short name")
    func hiddenParentDoesNotBorrowExtension() {
        let source = "struct Outer { fileprivate struct Foo { struct Inner {} } }\nextension Foo {}"
        #expect(edges(of: source) == ["Outer.Foo +-- Outer.Foo.Inner"])
    }

    @Test("a hidden parent two levels down is named by its full path")
    func deeplyHiddenParent() {
        let source = "struct A { fileprivate struct B { fileprivate struct C { struct D {} } } }\nstruct C {}"
        #expect(edges(of: source) == ["A.B.C +-- A.B.C.D"])
    }

    @Test("a public-only diagram names an internal parent by its qualified name")
    func publicOnlyFilter() {
        let source = "public struct Outer { struct Config { public struct Inner {} } }\npublic struct Config {}"
        let edges = edges(of: source, elements: ElementOptions(havingAccessLevel: [.public]))
        #expect(edges == ["Outer.Config +-- Outer.Config.Inner"])
    }

    // MARK: - Extension Parents

    /// An extension's name is already the extended type's full name; these pass before #67's fix
    /// too, and must keep passing.
    @Test("a type nested in an undrawn extension still hangs off the extended type")
    func undrawnExtensionParentStillResolves() {
        let source = "struct Outer { struct Foo {} }\nextension Outer.Foo { struct Inner {} }"
        for mode in [ExtensionVisualization.merged, .none] {
            #expect(edges(of: source, elements: ElementOptions(showExtensions: mode))
                == ["Outer +-- Outer.Foo", "Outer.Foo +-- Outer.Foo.Inner"], "\(mode)")
        }
    }

    /// Merging re-parents a type nested in an extension to the type it merged into (#107), so a
    /// hidden nested type's extension took the short-name fallback too.
    @Test("a type nested in a merged extension of a hidden nested type hangs off its qualified name")
    func mergedExtensionOfHiddenNestedType() {
        let source = "struct A { fileprivate struct B {} }\nextension A.B { struct Inner {} }\nstruct B {}"
        for mode in [ExtensionVisualization.merged, .none] {
            let elements = ElementOptions(showExtensions: mode)
            #expect(edges(of: source, elements: elements) == ["A.B +-- A.B.Inner"], "\(mode)")
            #expect(edges(of: source, .nomnoml, elements: elements) == ["[A.B] +- [A.B.Inner]"], "\(mode)")
        }
    }
}
