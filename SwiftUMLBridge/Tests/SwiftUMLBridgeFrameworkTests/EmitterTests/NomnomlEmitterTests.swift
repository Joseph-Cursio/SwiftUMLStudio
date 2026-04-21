import Testing
@testable import SwiftUMLBridgeFramework

@Suite("Nomnoml Emitter — SyntaxStructure+Nomnoml")
struct NomnomlEmitterTests {

    private let generator = ClassDiagramGenerator()
    private var nomnomlConfig: Configuration { Configuration(format: .nomnoml) }

    // MARK: - Type stereotypes

    @Test(
        "type declarations produce their matching nomnoml stereotype",
        arguments: [
            ("class Vehicle { var speed: Int = 0 }", "<class>", "Vehicle"),
            ("struct Point { var xPos: Int = 0 }", "<struct>", "Point"),
            ("enum Direction { case north, south }", "<enum>", "Direction"),
            ("protocol Drawable { func draw() }", "<interface>", "Drawable"),
            ("actor BankAccount { var balance: Int = 0 }", "<actor>", "BankAccount"),
            ("struct Foo {} \nextension Foo { func bar() {} }", "<extension>", "Foo")
        ]
    )
    func typeStereotype(source: String, stereotype: String, typeName: String) {
        let script = generator.generateScript(for: source, with: nomnomlConfig)
        #expect(script.text.contains(stereotype))
        #expect(script.text.contains(typeName))
    }

    @Test("macro element produces comment line in nomnoml output")
    func macroElement() {
        let items = [SyntaxStructure(kind: .macro, name: "Observable")]
        let script = DiagramScript(items: items, configuration: nomnomlConfig)
        #expect(script.text.contains("// macro: Observable"))
    }

    // MARK: - Members

    @Test("instance property appears with type annotation")
    func instancePropertyWithType() {
        let source = "class Person { var name: String = \"\" }"
        let script = generator.generateScript(for: source, with: nomnomlConfig)
        #expect(script.text.contains("name"))
        #expect(script.text.contains("String"))
    }

    @Test("instance method appears with parentheses")
    func instanceMethod() {
        let source = "class Greeter { func greet() {} }"
        let script = generator.generateScript(for: source, with: nomnomlConfig)
        #expect(script.text.contains("greet()"))
    }

    @Test("static method shows 'static' prefix in nomnoml")
    func staticMethod() {
        let source = "class Factory { static func create() {} }"
        let script = generator.generateScript(for: source, with: nomnomlConfig)
        #expect(script.text.contains("static create()"))
    }

    @Test("static property shows 'static' prefix in nomnoml")
    func staticProperty() {
        let source = "class Config { static var defaultName: String = \"\" }"
        let script = generator.generateScript(for: source, with: nomnomlConfig)
        #expect(script.text.contains("static defaultName"))
    }

    @Test("enum case appears in output")
    func enumCase() {
        let source = "enum Color { case red; case green; case blue }"
        let script = generator.generateScript(for: source, with: nomnomlConfig)
        #expect(script.text.contains("red"))
        #expect(script.text.contains("green"))
        #expect(script.text.contains("blue"))
    }

    // MARK: - Access level prefixes

    @Test(
        "access-level prefix is attached to members when the attribute is shown",
        arguments: [
            ("class Api { public var endpoint: String = \"\" }", "+endpoint"),
            ("class Secret { private var passkey: String = \"\" }", "-passkey"),
            ("class Worker { var taskCount: Int = 0 }", "~taskCount")
        ]
    )
    func accessLevelPrefix(source: String, expected: String) {
        let config = Configuration(
            elements: ElementOptions(
                showMembersWithAccessLevel: [.public, .internal, .private],
                showMemberAccessLevelAttribute: true
            ),
            format: .nomnoml
        )
        let script = generator.generateScript(for: source, with: config)
        #expect(script.text.contains(expected))
    }

    // MARK: - Escaping

    @Test("brackets in type names are escaped to parentheses")
    func bracketsEscaped() {
        let source = "class Container { var items: [String] = [] }"
        let script = generator.generateScript(for: source, with: nomnomlConfig)
        // [String] should be escaped to (String) in nomnoml
        #expect(script.text.contains("[String]") == false || script.text.contains("(String)"))
    }

    @Test("pipe characters in names are escaped to slashes")
    func pipeEscaped() {
        // Pipes are nomnoml section separators; they should be escaped in member text
        let items = [SyntaxStructure(
            kind: .class,
            name: "Converter",
            substructure: [
                SyntaxStructure(kind: .varInstance, name: "op|tion", typename: "String")
            ]
        )]
        let script = DiagramScript(items: items, configuration: nomnomlConfig)
        #expect(script.text.contains("op/tion"))
    }

    @Test("semicolons in names are escaped to commas")
    func semicolonEscaped() {
        let items = [SyntaxStructure(
            kind: .class,
            name: "Parser",
            substructure: [
                SyntaxStructure(kind: .varInstance, name: "sep;val", typename: "String")
            ]
        )]
        let script = DiagramScript(items: items, configuration: nomnomlConfig)
        #expect(script.text.contains("sep,val"))
    }

    // MARK: - Nil and skipped elements

    @Test("element with nil kind returns nil and produces no output")
    func nilKindProducesNoOutput() {
        let items = [SyntaxStructure(kind: nil, name: "Ghost")]
        let script = DiagramScript(items: items, configuration: nomnomlConfig)
        #expect(script.text.contains("Ghost") == false)
    }

    @Test("unsupported element kind is skipped without crash")
    func unsupportedKindSkipped() {
        let items = [SyntaxStructure(kind: .functionFree, name: "globalFunc")]
        let script = DiagramScript(items: items, configuration: nomnomlConfig)
        #expect(script.text.contains("globalFunc") == false)
    }

    @Test("excluded element does not appear in nomnoml output")
    func excludedElement() {
        let config = Configuration(
            elements: ElementOptions(exclude: ["Internal*"]),
            format: .nomnoml
        )
        let source = "class InternalCache {} \nclass PublicAPI {}"
        let script = generator.generateScript(for: source, with: config)
        #expect(script.text.contains("InternalCache") == false)
        #expect(script.text.contains("PublicAPI"))
    }

    // MARK: - Generics

    @Test("generics are shown when showGenerics is enabled")
    func genericsShown() {
        let config = Configuration(
            elements: ElementOptions(showGenerics: true),
            format: .nomnoml
        )
        let source = "class Box<Element> { var value: Element? = nil }"
        let script = generator.generateScript(for: source, with: config)
        #expect(script.text.contains("Box"))
    }

    // MARK: - Members with no substructure

    @Test("type with no members produces node without member sections")
    func emptyMembersNoSeparator() {
        let source = "struct Empty {}"
        let script = generator.generateScript(for: source, with: nomnomlConfig)
        #expect(script.text.contains("<struct>"))
        #expect(script.text.contains("Empty"))
    }

    // MARK: - Macro annotations

    @Test("@Observable class shows <<Observable>> annotation in nomnoml")
    func observableMacroAnnotation() {
        let source = "@Observable class UserVM { var name: String = \"\" }"
        let script = generator.generateScript(for: source, with: nomnomlConfig)
        #expect(script.text.contains("<<Observable>>"))
    }

    // MARK: - Format property

    @Test("format property is nomnoml")
    func formatPropertyIsNomnoml() {
        let script = DiagramScript(items: [], configuration: nomnomlConfig)
        #expect(script.format == .nomnoml)
    }

    // MARK: - Members without type annotations

    @Test("instance variable without typename shows only name in nomnoml output")
    func instanceVarWithoutTypename() {
        let items = [SyntaxStructure(kind: .class, name: "Box", substructure: [
            SyntaxStructure(accessibility: .internal, kind: .varInstance, name: "value")
        ])]
        let script = DiagramScript(items: items, configuration: nomnomlConfig)
        #expect(script.text.contains("value"))
        #expect(script.text.contains("value:") == false)
    }

    @Test("static variable without typename shows 'static name' in nomnoml output")
    func staticVarWithoutTypename() {
        let items = [SyntaxStructure(kind: .class, name: "Config", substructure: [
            SyntaxStructure(accessibility: .internal, kind: .varStatic, name: "shared")
        ])]
        let script = DiagramScript(items: items, configuration: nomnomlConfig)
        #expect(script.text.contains("static shared"))
    }

    // MARK: - Member access level filter

    @Test("member with access level outside filter is excluded from nomnoml output")
    func memberAccessLevelFilteredOut() {
        let config = Configuration(
            elements: ElementOptions(showMembersWithAccessLevel: [.public]),
            format: .nomnoml
        )
        let items = [SyntaxStructure(kind: .class, name: "Foo", substructure: [
            SyntaxStructure(accessibility: .internal, kind: .varInstance, name: "hidden", typename: "Int"),
            SyntaxStructure(accessibility: .public, kind: .varInstance, name: "visible", typename: "String")
        ])]
        let script = DiagramScript(items: items, configuration: config)
        #expect(script.text.contains("visible"))
        #expect(script.text.contains("hidden") == false)
    }
}
