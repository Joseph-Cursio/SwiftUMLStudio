import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing
import ViewInspector

@Suite("NodeInfoTooltip")
@MainActor
struct NodeInfoTooltipViewTests {

    private func strings(
        label: String = "Foo",
        stereotype: String? = nil,
        sourceLocation: SwiftUMLBridgeFramework.SourceLocation? = nil
    ) throws -> [String] {
        try NodeInfoTooltip(label: label, stereotype: stereotype, sourceLocation: sourceLocation)
            .inspect().findAll(ViewType.Text.self).map { try $0.string() }
    }

    @Test("label alone renders a single line")
    func labelOnly() throws {
        #expect(try strings(label: "Foo") == ["Foo"])
    }

    @Test("stereotype renders in guillemets before the label")
    func stereotype() throws {
        #expect(try strings(label: "Foo", stereotype: "actor") == ["«actor»", "Foo"])
    }

    @Test("empty stereotype is omitted")
    func emptyStereotype() throws {
        #expect(try strings(label: "Foo", stereotype: "") == ["Foo"])
    }

    @Test("source location renders as filename:line")
    func sourceLocation() throws {
        let location = SwiftUMLBridgeFramework.SourceLocation(filePath: "/tmp/Sources/Foo.swift", line: 12, column: 3)
        #expect(try strings(label: "Foo", sourceLocation: location) == ["Foo", "Foo.swift:12"])
    }

    @Test("source location with an empty path is omitted")
    func emptySourcePath() throws {
        let location = SwiftUMLBridgeFramework.SourceLocation(filePath: "", line: 12, column: 3)
        #expect(try strings(label: "Foo", sourceLocation: location) == ["Foo"])
    }

    @Test("tooltip is identifiable for UI tests")
    func accessibilityIdentifier() throws {
        let view = NodeInfoTooltip(label: "Foo", stereotype: nil, sourceLocation: nil)
        _ = try view.inspect().find(viewWithAccessibilityIdentifier: "nodeInfoTooltip")
    }
}
