import Testing
@testable import SwiftUMLBridgeFramework

/// `ElementKind.classNode` is the one table the Mermaid and Nomnoml emitters label nodes from (#209).
@Suite("ElementKind.classNode")
struct ElementKindClassNodeTests {

    /// Every kind a class diagram draws gets a node, except a macro, which each format draws as a
    /// comment. A processable kind with neither would be dropped with only a log line.
    @Test("every processable kind but macro has a node", arguments: ElementKind.processable)
    func processableKindsHaveANode(kind: ElementKind) {
        #expect((kind.classNode == nil) == (kind == .macro), "\(kind)")
    }

    @Test("relationships and stereotypes", arguments: [
        (ElementKind.class, "inherits", "class"),
        (.struct, "inherits", "struct"),
        (.extension, "ext", "extension"),
        (.enum, "", "enum"),
        (.protocol, "conforms to", "protocol"),
        (.actor, "actor", "actor")
    ])
    func table(kind: ElementKind, relationship: String, stereotype: String) throws {
        let node = try #require(kind.classNode)
        #expect(node.relationship == relationship)
        #expect(node.stereotype == stereotype)
    }
}
