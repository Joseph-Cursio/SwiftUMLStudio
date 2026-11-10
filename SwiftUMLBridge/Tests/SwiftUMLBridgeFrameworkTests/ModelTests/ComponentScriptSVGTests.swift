import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

@Suite("ComponentScript SVG plumbing")
struct ComponentScriptSVGTests {

    @Test("svg configuration populates componentLayout and emits SVG text")
    func svgFormatPopulatesLayout() {
        let model = ComponentModel(
            components: [Component(name: "Lib", kind: .library)]
        )
        var configuration = Configuration.default
        configuration.format = .svg
        let script = ComponentScript(model: model, configuration: configuration)
        #expect(script.format == .svg)
        #expect(script.text.contains("<svg"))
        #expect(script.componentLayout != nil)
        #expect(script.componentLayout?.components.count == 1)
    }

    @Test("plantuml configuration leaves componentLayout nil")
    func plantUMLFormatLeavesLayoutNil() {
        let model = ComponentModel(
            components: [Component(name: "Lib", kind: .library)]
        )
        let script = ComponentScript(model: model, configuration: .default)
        #expect(script.format == .plantuml)
        #expect(script.componentLayout == nil)
    }

    @Test("nomnoml configuration falls back to mermaid and leaves componentLayout nil")
    func nomnomlFallsBackToMermaid() {
        let model = ComponentModel(
            components: [Component(name: "Lib", kind: .library)]
        )
        var configuration = Configuration.default
        configuration.format = .nomnoml
        let script = ComponentScript(model: model, configuration: configuration)
        // Nomnoml has no component-diagram dialect — fall back to Mermaid, like the
        // sequence/activity/state/ER emitters, so presenters render it locally.
        var mermaidConfiguration = Configuration.default
        mermaidConfiguration.format = .mermaid
        let mermaidScript = ComponentScript(model: model, configuration: mermaidConfiguration)
        #expect(script.format == .mermaid)
        #expect(script.text == mermaidScript.text)
        #expect(script.componentLayout == nil)
    }
}
