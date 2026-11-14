@testable import SwiftUMLBridgeFramework
import Testing

@Suite("LayoutNode.sourceLocation")
struct LayoutNodeSourceLocationTests {

    @Test("init defaults sourceLocation to nil")
    func defaultIsNil() {
        let node = LayoutNode(id: "A", label: "A")
        #expect(node.sourceLocation == nil)
    }

    @Test("init can take a sourceLocation")
    func takesArgument() {
        let location = SourceLocation(filePath: "/Foo.swift", line: 10, column: 6)
        let node = LayoutNode(id: "Foo", label: "Foo", sourceLocation: location)
        #expect(node.sourceLocation == location)
    }
}
