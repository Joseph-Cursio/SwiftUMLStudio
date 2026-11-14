@testable import SwiftUMLBridgeFramework
import Testing

@Suite("Mermaid DiagramScript")
struct MermaidScriptTests {

    private var mermaidConfig: Configuration {
        Configuration(format: .mermaid)
    }

    @Test("classDiagram is first line")
    func classDiagramIsFirstLine() {
        let script = DiagramScript(items: [], configuration: mermaidConfig)
        let firstLine = script.text.components(separatedBy: "\n").first
        #expect(firstLine == "classDiagram")
    }

    @Test("no @startuml in Mermaid output")
    func noStartuml() {
        let script = DiagramScript(items: [], configuration: mermaidConfig)
        #expect(script.text.contains("@startuml") == false)
    }

    @Test("no @enduml in Mermaid output")
    func noEnduml() {
        let script = DiagramScript(items: [], configuration: mermaidConfig)
        #expect(script.text.contains("@enduml") == false)
    }

    @Test("class node appears in Mermaid output")
    func classNodeAppearsInOutput() {
        let generator = ClassDiagramGenerator()
        let script = generator.generateScript(for: "class Foo {}", with: mermaidConfig)
        #expect(script.text.contains("Foo"))
    }

    @Test("actor node appears in Mermaid output")
    func actorNodeAppearsInOutput() {
        let generator = ClassDiagramGenerator()
        let source = "actor ImageCache { var count: Int = 0 }"
        let script = generator.generateScript(for: source, with: mermaidConfig)
        #expect(script.text.contains("ImageCache"))
    }

    @Test("defaultStyling is empty for Mermaid format")
    func defaultStylingIsEmpty() {
        let script = DiagramScript(items: [], configuration: mermaidConfig)
        #expect(script.defaultStyling.isEmpty)
    }
}
