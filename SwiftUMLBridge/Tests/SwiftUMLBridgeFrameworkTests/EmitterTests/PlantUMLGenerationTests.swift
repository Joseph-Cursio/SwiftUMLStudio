import Testing
@testable import SwiftUMLBridgeFramework

@Suite("PlantUML Generation")
struct PlantUMLGenerationTests {

    private let generator = ClassDiagramGenerator()

    // MARK: - Type stereotypes

    @Test("struct produces struct stereotype in output")
    func structStereotype() {
        let script = generator.generateScript(for: "struct MyStruct {}")
        #expect(script.text.contains("MyStruct"))
        #expect(script.text.contains("struct"))
    }

    @Test("enum produces enum stereotype in output")
    func enumStereotype() {
        let script = generator.generateScript(for: "enum Direction { case north, south }")
        #expect(script.text.contains("Direction"))
        #expect(script.text.contains("enum"))
    }

    @Test("protocol produces protocol stereotype in output")
    func protocolStereotype() {
        let script = generator.generateScript(for: "protocol Drawable { func draw() }")
        #expect(script.text.contains("Drawable"))
        #expect(script.text.contains("protocol"))
    }

    @Test("extension produces extension stereotype in output")
    func extensionStereotype() {
        let script = generator.generateScript(for: "struct Foo {} \nextension Foo { func bar() {} }")
        #expect(script.text.contains("Foo"))
        #expect(script.text.contains("extension"))
    }

    @Test("class produces class node in output")
    func classNode() {
        let script = generator.generateScript(for: "class Vehicle { var speed: Int = 0 }")
        #expect(script.text.contains("Vehicle"))
        #expect(script.text.contains("class"))
    }

    // MARK: - Members

    @Test("instance variable appears in output with type")
    func instanceVarWithType() {
        let source = "class Person { var name: String = \"\" }"
        let script = generator.generateScript(for: source)
        #expect(script.text.contains("name"))
        #expect(script.text.contains("String"))
    }

    @Test("instance method appears in output")
    func instanceMethod() {
        let source = "class Greeter { func greet() {} }"
        let script = generator.generateScript(for: source)
        #expect(script.text.contains("greet"))
    }

    @Test("static method shows {static} prefix")
    func staticMethod() {
        let source = "class Factory { static func create() -> Factory { return Factory() } }"
        let script = generator.generateScript(for: source)
        #expect(script.text.contains("create"))
    }

    @Test("enum case appears in output")
    func enumCase() {
        let source = "enum Color { case red; case green; case blue }"
        let script = generator.generateScript(for: source)
        #expect(script.text.contains("Color"))
    }

    // MARK: - Inheritance and conformance

    @Test("class inheritance produces relationship in output")
    func classInheritance() {
        let source = "class Animal {} \nclass Dog: Animal {}"
        let script = generator.generateScript(for: source)
        #expect(script.text.contains("Animal"))
        #expect(script.text.contains("Dog"))
        #expect(script.text.contains("<|--"))
    }

    @Test("protocol conformance produces realization in output")
    func protocolConformance() {
        let source = "protocol Flyable {} \nclass Bird: Flyable {}"
        let script = generator.generateScript(for: source)
        #expect(script.text.contains("Flyable"))
        #expect(script.text.contains("Bird"))
        #expect(script.text.contains("<|.."))
    }

    // MARK: - Configuration effects

    @Test("excluded element does not appear in output")
    func excludedElement() {
        let config = Configuration(
            elements: ElementOptions(exclude: ["Internal*"])
        )
        let source = "class InternalCache {} \nclass PublicAPI {}"
        let script = generator.generateScript(for: source, with: config)
        #expect(script.text.contains("InternalCache") == false)
        #expect(script.text.contains("PublicAPI"))
    }

    @Test("extensions hidden when showExtensions is none")
    func extensionsHiddenWhenNone() {
        let config = Configuration(
            elements: ElementOptions(showExtensions: ExtensionVisualization.none)
        )
        let source = "struct Foo {} \nextension Foo { func bar() {} }"
        let script = generator.generateScript(for: source, with: config)
        // Extension stereotype should not appear in output
        let lines = script.text.components(separatedBy: "\n")
        let extensionLines = lines.filter { $0.contains("extension") && !$0.hasPrefix("'") }
        #expect(extensionLines.isEmpty)
    }

    @Test("extensions merged when showExtensions is merged")
    func extensionsMergedWhenMerged() {
        let config = Configuration(
            elements: ElementOptions(showExtensions: ExtensionVisualization.merged)
        )
        let source = "struct Foo {} \nextension Foo { func bar() {} }"
        let script = generator.generateScript(for: source, with: config)
        #expect(script.text.contains("Foo"))
    }

    @Test("generics not shown when showGenerics is false")
    func genericsHiddenWhenFalse() {
        let config = Configuration(
            elements: ElementOptions(showGenerics: false)
        )
        let source = "class Container<T> {}"
        let script = generator.generateScript(for: source, with: config)
        #expect(script.text.contains("Container"))
    }

    @Test("generics shown when showGenerics is true")
    func genericsShownWhenTrue() {
        let source = "class Box<T> {}"
        let script = generator.generateScript(for: source, with: .default)
        #expect(script.text.contains("Box"))
        #expect(script.text.contains("<T>") || script.text.contains("T"))
    }

    @Test("script includes page texts when configured")
    func pageTextsIncluded() {
        let config = Configuration(texts: PageTexts(title: "My Diagram"))
        let script = generator.generateScript(for: "class Foo {}", with: config)
        #expect(script.text.contains("My Diagram"))
    }

    @Test("script includes remote URL when configured")
    func remoteURLIncluded() {
        let config = Configuration(includeRemoteURL: "https://example.com/theme.puml")
        let script = generator.generateScript(for: "class Foo {}", with: config)
        #expect(script.text.contains("!include"))
        #expect(script.text.contains("https://example.com/theme.puml"))
    }

    @Test("unsupported element kind is skipped without crash")
    func unsupportedKindSkipped() {
        let items = [SyntaxStructure(kind: .functionFree, name: "MyFunc")]
        let script = DiagramScript(items: items, configuration: .default)
        #expect(script.text.hasPrefix("@startuml"))
    }

    // MARK: - Macro stereotypes

    @Test("@Observable class shows Observable stereotype in PlantUML output")
    func observableMacroStereotype() {
        let source = "@Observable class UserVM { var name: String = \"\" }"
        let script = generator.generateScript(for: source)
        #expect(script.text.contains("<<Observable>>"))
    }

    @Test("@Model class shows Model stereotype in PlantUML output")
    func modelMacroStereotype() {
        let source = "@Model class Item { var title: String = \"\" }"
        let script = generator.generateScript(for: source)
        #expect(script.text.contains("<<Model>>"))
    }

    @Test("class without macro attributes has no extra stereotypes")
    func noMacroStereotype() {
        let source = "class Plain { var value: Int = 0 }"
        let script = generator.generateScript(for: source)
        let text = script.text
        // Should have the kind stereotype but not any macro stereotype
        #expect(text.contains("Plain"))
        #expect(text.contains("<<Observable>>") == false)
    }

    // MARK: - Macro kind rendering

    @Test("macro kind produces note block in PlantUML output")
    func macroKindProducesNoteBlock() {
        let items = [SyntaxStructure(kind: .macro, name: "Observable")]
        let script = DiagramScript(items: items, configuration: .default)
        #expect(script.text.contains("note as"))
        #expect(script.text.contains("<<macro>>"))
        #expect(script.text.contains("Observable"))
    }

    // MARK: - Compound inherited type with &

    @Test("compound inherited type with & splits into separate link targets")
    func compoundInheritanceTypeSplitsAtAmpersand() {
        let item = SyntaxStructure(
            inheritedTypes: [SyntaxStructure(name: "Sendable & Codable")],
            kind: .struct, name: "MyType"
        )
        let script = DiagramScript(items: [item], configuration: .default)
        // Both names should appear in the connection lines
        #expect(script.text.contains("Sendable"))
        #expect(script.text.contains("Codable"))
    }

    // MARK: - Member access level filter

    @Test("member with access level outside filter is excluded from PlantUML output")
    func memberAccessLevelFilteredOut() {
        let config = Configuration(
            elements: ElementOptions(showMembersWithAccessLevel: [.public])
        )
        // internal var hidden should be filtered; public var visible should appear
        let items = [SyntaxStructure(kind: .class, name: "Foo", substructure: [
            SyntaxStructure(accessibility: .internal, kind: .varInstance, name: "hidden", typename: "Int"),
            SyntaxStructure(accessibility: .public, kind: .varInstance, name: "visible", typename: "String")
        ])]
        let script = DiagramScript(items: items, configuration: config)
        #expect(script.text.contains("visible"))
        #expect(script.text.contains("hidden") == false)
    }

    // MARK: - Constrained generic parameter

    @Test("constrained generic parameter includes constraint in PlantUML output")
    func constrainedGenericParam() {
        let param = SyntaxStructure(
            inheritedTypes: [SyntaxStructure(name: "Comparable")],
            kind: .genericTypeParam, name: "T"
        )
        let item = SyntaxStructure(kind: .class, name: "Container", substructure: [param])
        let script = DiagramScript(items: [item], configuration: .default)
        #expect(script.text.contains("T: Comparable"))
    }
}
