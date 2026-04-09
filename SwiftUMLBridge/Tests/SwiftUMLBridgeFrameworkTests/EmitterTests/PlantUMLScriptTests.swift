import Testing
@testable import SwiftUMLBridgeFramework

@Suite("DiagramScript")
struct DiagramScriptTests {

    @Test("empty input produces valid @startuml/@enduml")
    func emptyInputProducesValidScript() {
        let script = DiagramScript(items: [], configuration: .default)
        #expect(script.text.hasPrefix("@startuml"))
        #expect(script.text.hasSuffix("@enduml"))
    }

    @Test("script contains @startuml as first line")
    func startumlIsFirstLine() {
        let script = DiagramScript(items: [], configuration: .default)
        let firstLine = script.text.components(separatedBy: "\n").first
        #expect(firstLine == "@startuml")
    }

    @Test("script contains @enduml as last line")
    func endumlIsLastLine() {
        let script = DiagramScript(items: [], configuration: .default)
        let lastLine = script.text.components(separatedBy: "\n").last(where: { !$0.isEmpty })
        #expect(lastLine == "@enduml")
    }

    @Test("class structure appears in output")
    func classStructureAppearsInOutput() {
        let generator = ClassDiagramGenerator()
        let script = generator.generateScript(for: "class Foo {}", with: .default)
        #expect(script.text.contains("Foo"))
    }

    @Test("actor structure appears in output")
    func actorStructureAppearsInOutput() {
        let generator = ClassDiagramGenerator()
        let source = "actor ImageCache { var count: Int = 0 }"
        let script = generator.generateScript(for: source, with: .default)
        #expect(script.text.contains("ImageCache"))
    }

    @Test("encodeText returns non-empty string")
    func encodeTextNonEmpty() {
        let script = DiagramScript(items: [], configuration: .default)
        let encoded = script.encodeText()
        #expect(encoded.isEmpty == false)
    }

    @Test("default styling includes hide empty members")
    func defaultStylingContainsHideEmptyMembers() {
        let script = DiagramScript(items: [], configuration: .default)
        #expect(script.text.contains("hide empty members"))
    }

    @Test("defaultStyling returns empty string when both command arrays are empty")
    func defaultStylingEmptyWhenNoCommands() {
        let config = Configuration(hideShowCommands: [], skinparamCommands: [])
        let script = DiagramScript(items: [], configuration: config)
        #expect(script.defaultStyling == "")
    }

    // MARK: - Nomnoml title and footer comments

    @Test("nomnoml output includes title comment when texts.title is set")
    func nomnomlTitleComment() {
        let config = Configuration(texts: PageTexts(title: "My Title"), format: .nomnoml)
        let script = DiagramScript(items: [], configuration: config)
        #expect(script.text.contains("// title: My Title"))
    }

    @Test("nomnoml output includes footer comment when texts.footer is set")
    func nomnomlFooterComment() {
        let config = Configuration(texts: PageTexts(footer: "Page 1"), format: .nomnoml)
        let script = DiagramScript(items: [], configuration: config)
        #expect(script.text.contains("// footer: Page 1"))
    }
}
