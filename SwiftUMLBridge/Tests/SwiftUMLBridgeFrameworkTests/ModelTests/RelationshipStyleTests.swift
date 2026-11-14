@testable import SwiftUMLBridgeFramework
import Testing

@Suite("RelationshipStyle")
struct RelationshipStyleTests {

    @Test("default RelationshipStyle has plain line style")
    func defaultLineStyle() {
        let style = RelationshipStyle()
        #expect(style.lineStyle == .plain)
    }

    @Test("default RelationshipStyle has black line color")
    func defaultLineColor() {
        let style = RelationshipStyle()
        #expect(style.lineColor == .black)
    }

    @Test("default RelationshipStyle has black text color")
    func defaultTextColor() {
        let style = RelationshipStyle()
        #expect(style.textColor == .black)
    }

    @Test("plantuml string has correct format with defaults")
    func plantumlDefaultFormat() {
        let style = RelationshipStyle()
        #expect(style.plantuml == "#line:black;line.plain;text:black")
    }

    @Test("plantuml string includes lineStyle component")
    func plantumlContainsLineStyle() {
        let style = RelationshipStyle()
        #expect(style.plantuml.contains("line.plain"))
    }

    @Test("plantuml string includes lineColor component")
    func plantumlContainsLineColor() {
        let style = RelationshipStyle()
        #expect(style.plantuml.contains("line:black"))
    }

    @Test("plantuml string includes textColor component")
    func plantumlContainsTextColor() {
        let style = RelationshipStyle()
        #expect(style.plantuml.contains("text:black"))
    }

    @Test("RelationshipInlineStyle bold raw value")
    func boldRawValue() {
        #expect(RelationshipInlineStyle.bold.rawValue == "bold")
    }

    @Test("RelationshipInlineStyle dashed raw value")
    func dashedRawValue() {
        #expect(RelationshipInlineStyle.dashed.rawValue == "dashed")
    }

    @Test("RelationshipInlineStyle dotted raw value")
    func dottedRawValue() {
        #expect(RelationshipInlineStyle.dotted.rawValue == "dotted")
    }

    @Test("RelationshipInlineStyle hidden raw value")
    func hiddenRawValue() {
        #expect(RelationshipInlineStyle.hidden.rawValue == "hidden")
    }

    @Test("RelationshipInlineStyle plain raw value")
    func plainRawValue() {
        #expect(RelationshipInlineStyle.plain.rawValue == "plain")
    }
}
