import Testing
@testable import SwiftUMLBridgeFramework

/// `DrawnEdgeEnds.extendedType(of:)` is what an extension's `ext` edge ends on (#72), so its `nil`
/// must not rest on the order in which `uniqName` records aliases.
@Suite("DrawnEdgeEnds — the type an extension extends")
struct DrawnEdgeEndsTests {

    private func declared(
        _ kind: ElementKind, _ name: String, in file: String, access: ElementAccessibility? = nil
    ) -> SyntaxStructure {
        let item = SyntaxStructure(accessibility: access, kind: kind, name: name)
        item.sourceLocation = SourceLocation(filePath: file, line: 1, column: 1)
        return item
    }

    private func extendedType(
        of anExtension: SyntaxStructure, drawing drawn: [SyntaxStructure], among prepared: [SyntaxStructure]
    ) -> SyntaxStructure? {
        DrawnEdgeEnds(drawing: Set(drawn), among: prepared).extendedType(of: anExtension)
    }

    @Test("an extension of a drawn type finds that type")
    func drawnType() {
        let type = declared(.struct, "Foo", in: "A.swift")
        let anExtension = declared(.extension, "Foo", in: "B.swift")
        let items = [type, anExtension]
        #expect(extendedType(of: anExtension, drawing: items, among: items) === type)
    }

    @Test("an extension of a type outside the diagram finds none, not itself")
    func outsideType() {
        let anExtension = declared(.extension, "String", in: "A.swift")
        #expect(extendedType(of: anExtension, drawing: [anExtension], among: [anExtension]) == nil)
    }

    @Test("an extension of a hidden type finds none, not a drawn type of its name")
    func hiddenType() {
        let drawnType = declared(.struct, "Foo", in: "A.swift")
        let hiddenType = declared(.struct, "Foo", in: "B.swift", access: .fileprivate)
        let anExtension = declared(.extension, "Foo", in: "B.swift")
        let found = extendedType(
            of: anExtension, drawing: [drawnType, anExtension], among: [drawnType, hiddenType, anExtension]
        )
        #expect(found == nil)
    }
}
