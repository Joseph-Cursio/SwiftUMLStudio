import Testing
@testable import SwiftUMLBridgeFramework

@Suite("Mermaid Generation")
struct MermaidGenerationTests {

    private let generator = ClassDiagramGenerator()
    private var mermaidConfig: Configuration { Configuration(format: .mermaid) }

    // MARK: - Type stereotypes

    @Test("struct produces struct stereotype in Mermaid output")
    func structStereotype() {
        let script = generator.generateScript(for: "struct MyStruct {}", with: mermaidConfig)
        #expect(script.text.contains("MyStruct"))
        #expect(script.text.contains("struct"))
    }

    @Test("enum produces enum stereotype in Mermaid output")
    func enumStereotype() {
        let script = generator.generateScript(for: "enum Direction { case north, south }", with: mermaidConfig)
        #expect(script.text.contains("Direction"))
        #expect(script.text.contains("enum"))
    }

    @Test("protocol produces protocol stereotype in Mermaid output")
    func protocolStereotype() {
        let script = generator.generateScript(for: "protocol Drawable { func draw() }", with: mermaidConfig)
        #expect(script.text.contains("Drawable"))
        #expect(script.text.contains("protocol"))
    }

    @Test("extension produces extension stereotype in Mermaid output")
    func extensionStereotype() {
        let script = generator.generateScript(
            for: "struct Foo {} \nextension Foo { func bar() {} }", with: mermaidConfig
        )
        #expect(script.text.contains("Foo"))
        #expect(script.text.contains("extension"))
    }

    @Test("class produces class node in Mermaid output")
    func classNode() {
        let script = generator.generateScript(for: "class Vehicle { var speed: Int = 0 }", with: mermaidConfig)
        #expect(script.text.contains("Vehicle"))
        #expect(script.text.contains("class"))
    }

    // MARK: - Members

    @Test("instance variable appears in Mermaid output")
    func instanceVarWithType() {
        let source = "class Person { var name: String = \"\" }"
        let script = generator.generateScript(for: source, with: mermaidConfig)
        #expect(script.text.contains("name"))
        #expect(script.text.contains("String"))
    }

    @Test("instance method appears in Mermaid output")
    func instanceMethod() {
        let source = "class Greeter { func greet() {} }"
        let script = generator.generateScript(for: source, with: mermaidConfig)
        #expect(script.text.contains("greet"))
    }

    @Test("static method shows $ classifier in Mermaid output")
    func staticMethod() {
        let source = "class Factory { static func create() -> Factory { return Factory() } }"
        let script = generator.generateScript(for: source, with: mermaidConfig)
        #expect(script.text.contains("create"))
        #expect(script.text.contains("$"))
    }

    @Test("enum case appears in Mermaid output")
    func enumCase() {
        let source = "enum Color { case red; case green; case blue }"
        let script = generator.generateScript(for: source, with: mermaidConfig)
        #expect(script.text.contains("Color"))
    }

    // MARK: - Relationships

    @Test("class inheritance produces <|-- relationship in Mermaid output")
    func classInheritance() {
        let source = "class Animal {} \nclass Dog: Animal {}"
        let script = generator.generateScript(for: source, with: mermaidConfig)
        #expect(script.text.contains("Animal"))
        #expect(script.text.contains("Dog"))
        #expect(script.text.contains("<|--"))
    }

    @Test("protocol conformance produces <|.. relationship in Mermaid output")
    func protocolConformance() {
        let source = "protocol Flyable {} \nclass Bird: Flyable {}"
        let script = generator.generateScript(for: source, with: mermaidConfig)
        #expect(script.text.contains("Flyable"))
        #expect(script.text.contains("Bird"))
        #expect(script.text.contains("<|.."))
    }

    @Test("extension link produces <.. relationship in Mermaid output")
    func extensionLink() {
        let source = "struct Foo {} \nextension Foo { func bar() {} }"
        let script = generator.generateScript(for: source, with: mermaidConfig)
        #expect(script.text.contains("<.."))
    }

    // MARK: - Configuration effects

    @Test("excluded element does not appear in Mermaid output")
    func excludedElement() {
        let config = Configuration(
            elements: ElementOptions(exclude: ["Internal*"]),
            format: .mermaid
        )
        let source = "class InternalCache {} \nclass PublicAPI {}"
        let script = generator.generateScript(for: source, with: config)
        #expect(script.text.contains("InternalCache") == false)
        #expect(script.text.contains("PublicAPI"))
    }

    @Test("extensions hidden when showExtensions is none in Mermaid")
    func extensionsHiddenWhenNone() {
        let config = Configuration(
            elements: ElementOptions(showExtensions: ExtensionVisualization.none),
            format: .mermaid
        )
        let source = "struct Foo {} \nextension Foo { func bar() {} }"
        let script = generator.generateScript(for: source, with: config)
        let lines = script.text.components(separatedBy: "\n")
        let extensionLines = lines.filter { $0.contains("extension") && !$0.hasPrefix("%%") }
        #expect(extensionLines.isEmpty)
    }

    @Test("page texts emitted as Mermaid comments")
    func pageTextsAsMermaidComments() {
        let config = Configuration(texts: PageTexts(title: "My Diagram"), format: .mermaid)
        let script = generator.generateScript(for: "class Foo {}", with: config)
        #expect(script.text.contains("%% title: My Diagram"))
    }

    @Test("no nested-type +-- connections in Mermaid output")
    func noNestedTypeConnections() {
        let config = Configuration(
            elements: ElementOptions(showNestedTypes: true),
            format: .mermaid
        )
        let source = "class Outer { class Inner {} }"
        let script = generator.generateScript(for: source, with: config)
        #expect(script.text.contains("+--") == false)
    }

    @Test("unsupported element kind is skipped in Mermaid without crash")
    func unsupportedKindSkipped() {
        let items = [SyntaxStructure(kind: .functionFree, name: "MyFunc")]
        let script = DiagramScript(items: items, configuration: mermaidConfig)
        #expect(script.text.hasPrefix("classDiagram"))
    }

    @Test("format property is mermaid")
    func formatPropertyIsMermaid() {
        let script = DiagramScript(items: [], configuration: mermaidConfig)
        #expect(script.format == .mermaid)
    }

    @Test("PlantUML format property is plantuml")
    func formatPropertyIsPlantuml() {
        let script = DiagramScript(items: [], configuration: .default)
        #expect(script.format == .plantuml)
    }

    // MARK: - Macro stereotypes

    @Test("@Observable class shows Observable stereotype in Mermaid output")
    func observableMacroStereotype() {
        let source = "@Observable class UserVM { var name: String = \"\" }"
        let script = generator.generateScript(for: source, with: mermaidConfig)
        #expect(script.text.contains("<<Observable>>"))
    }

    @Test("@Model class shows Model stereotype in Mermaid output")
    func modelMacroStereotype() {
        let source = "@Model class Item { var title: String = \"\" }"
        let script = generator.generateScript(for: source, with: mermaidConfig)
        #expect(script.text.contains("<<Model>>"))
    }

    @Test("class without macro attributes has no extra stereotypes in Mermaid")
    func noMacroStereotype() {
        let source = "class Plain { var value: Int = 0 }"
        let script = generator.generateScript(for: source, with: mermaidConfig)
        #expect(script.text.contains("Plain"))
        #expect(script.text.contains("<<Observable>>") == false)
    }

    // MARK: - Static members

    @Test("static method renders with $ suffix in Mermaid output")
    func staticMethodRendersWithDollarSuffix() {
        let source = "class Factory { static func create() -> Factory { Factory() } }"
        let script = generator.generateScript(for: source, with: mermaidConfig)
        #expect(script.text.contains("create()$"))
    }

    @Test("static property renders with $ suffix in Mermaid output")
    func staticPropertyRendersWithDollarSuffix() {
        let source = "class Cache { static var shared: Cache = Cache() }"
        let script = generator.generateScript(for: source, with: mermaidConfig)
        #expect(script.text.contains("shared") && script.text.contains("$"))
    }

    @Test("enum cases render as plain member names in Mermaid output")
    func enumCasesRenderAsPlainNames() {
        // SourceKit parses comma-separated cases as one element (first name only);
        // use separate case declarations so each case appears as its own member.
        let source = "enum Direction { case north\ncase south\ncase east\ncase west }"
        let script = generator.generateScript(for: source, with: mermaidConfig)
        #expect(script.text.contains("north"))
        #expect(script.text.contains("south"))
    }

    // MARK: - Members without type annotations

    @Test("instance variable without typename shows only name in Mermaid output")
    func instanceVarWithoutTypename() {
        let items = [SyntaxStructure(kind: .struct, name: "Container", substructure: [
            SyntaxStructure(accessibility: .internal, kind: .varInstance, name: "value")
        ])]
        let script = DiagramScript(items: items, configuration: mermaidConfig)
        #expect(script.text.contains("value"))
        // No colon-separated type should appear
        #expect(script.text.contains("value :") == false)
    }

    @Test("static variable without typename shows name with $ in Mermaid output")
    func staticVarWithoutTypename() {
        let items = [SyntaxStructure(kind: .class, name: "Config", substructure: [
            SyntaxStructure(accessibility: .internal, kind: .varStatic, name: "shared")
        ])]
        let script = DiagramScript(items: items, configuration: mermaidConfig)
        #expect(script.text.contains("shared$"))
    }

    // MARK: - Member access level filter

    @Test("member with access level outside filter is excluded from Mermaid output")
    func memberAccessLevelFilteredOut() {
        let config = Configuration(
            elements: ElementOptions(showMembersWithAccessLevel: [.public]),
            format: .mermaid
        )
        let items = [SyntaxStructure(kind: .class, name: "Foo", substructure: [
            SyntaxStructure(accessibility: .internal, kind: .varInstance, name: "hidden", typename: "Int"),
            SyntaxStructure(accessibility: .public, kind: .varInstance, name: "visible", typename: "String")
        ])]
        let script = DiagramScript(items: items, configuration: config)
        #expect(script.text.contains("visible"))
        #expect(script.text.contains("hidden") == false)
    }

    // MARK: - Macro kind rendering

    @Test("macro kind produces comment line in Mermaid output")
    func macroKindProducesComment() {
        let items = [SyntaxStructure(kind: .macro, name: "Observable")]
        let script = DiagramScript(items: items, configuration: mermaidConfig)
        #expect(script.text.contains("%% macro:"))
        #expect(script.text.contains("Observable"))
    }
}
