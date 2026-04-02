import Testing
@testable import SwiftUMLBridgeFramework
import SwiftParser
import SwiftSyntax

// MARK: - Helpers

private func build(_ source: String) -> [SyntaxStructure] {
    let sourceFile = Parser.parse(source: source)
    let builder = SyntaxStructureBuilder(viewMode: .sourceAccurate)
    builder.walk(sourceFile)
    return builder.topLevelItems
}

@Suite("SyntaxStructureBuilder")
struct SyntaxStructureBuilderTests {

    // MARK: - Type declaration kinds

    @Test("class declaration → kind .class")
    func classKind() {
        let items = build("class Foo {}")
        #expect(items.first?.kind == .class)
        #expect(items.first?.name == "Foo")
    }

    @Test("struct declaration → kind .struct")
    func structKind() {
        let items = build("struct Point {}")
        #expect(items.first?.kind == .struct)
        #expect(items.first?.name == "Point")
    }

    @Test("enum declaration → kind .enum")
    func enumKind() {
        let items = build("enum Direction {}")
        #expect(items.first?.kind == .enum)
        #expect(items.first?.name == "Direction")
    }

    @Test("actor declaration → kind .actor (not .class)")
    func actorKind() {
        let items = build("actor ImageCache {}")
        #expect(items.first?.kind == .actor)
        #expect(items.first?.name == "ImageCache")
    }

    @Test("protocol declaration → kind .protocol")
    func protocolKind() {
        let items = build("protocol Drawable {}")
        #expect(items.first?.kind == .protocol)
        #expect(items.first?.name == "Drawable")
    }

    @Test("extension declaration → kind .extension")
    func extensionKind() {
        let items = build("extension Foo {}")
        #expect(items.first?.kind == .extension)
        #expect(items.first?.name == "Foo")
    }

    @Test("multiple top-level types all captured")
    func multipleTopLevelTypes() {
        let items = build("class A {} struct B {} enum C {}")
        #expect(items.count == 3)
    }

    // MARK: - Accessibility

    @Test("public class → accessibility .public")
    func publicAccessibility() {
        let items = build("public class Foo {}")
        #expect(items.first?.accessibility == .public)
    }

    @Test("open class → accessibility .open")
    func openAccessibility() {
        let items = build("open class Foo {}")
        #expect(items.first?.accessibility == .open)
    }

    @Test("private struct → accessibility .private")
    func privateAccessibility() {
        let items = build("private struct Bar {}")
        #expect(items.first?.accessibility == .private)
    }

    @Test("fileprivate enum → accessibility .fileprivate")
    func fileprivateAccessibility() {
        let items = build("fileprivate enum Baz {}")
        #expect(items.first?.accessibility == .fileprivate)
    }

    @Test("class with no modifier → accessibility .internal")
    func defaultInternalAccessibility() {
        let items = build("class Foo {}")
        #expect(items.first?.accessibility == .internal)
    }

    // MARK: - Inherited types

    @Test("class with superclass → inheritedTypes contains superclass name")
    func classSuperclass() {
        let items = build("class Dog: Animal {}")
        #expect(items.first?.inheritedTypes?.first?.name == "Animal")
    }

    @Test("class conforming to protocol → inheritedTypes contains protocol name")
    func classProtocolConformance() {
        let items = build("class Bird: Flyable {}")
        let names = items.first?.inheritedTypes?.compactMap(\.name) ?? []
        #expect(names.contains("Flyable"))
    }

    @Test("compound inherited type A & B splits into two entries")
    func compoundInheritedType() {
        let items = build("class Foo: Bar & Baz {}")
        let names = items.first?.inheritedTypes?.compactMap(\.name) ?? []
        #expect(names.contains("Bar"))
        #expect(names.contains("Baz"))
        #expect(names.count == 2)
    }

    @Test("type with no inheritance → inheritedTypes is nil")
    func noInheritance() {
        let items = build("class Foo {}")
        #expect(items.first?.inheritedTypes == nil)
    }

    // MARK: - Generic parameters

    @Test("generic class has genericTypeParam in substructure")
    func genericTypeParam() {
        let items = build("class Box<T> {}")
        let params = items.first?.substructure?.filter { $0.kind == .genericTypeParam } ?? []
        #expect(params.count == 1)
        #expect(params.first?.name == "T")
    }

    @Test("generic type with constraint captures constraint name")
    func genericTypeParamWithConstraint() {
        let items = build("class Sorted<T: Comparable> {}")
        let param = items.first?.substructure?.first { $0.kind == .genericTypeParam }
        #expect(param?.name == "T")
        #expect(param?.inheritedTypes?.first?.name == "Comparable")
    }

    @Test("multiple generic params all captured")
    func multipleGenericParams() {
        let items = build("class Pair<A, B> {}")
        let params = items.first?.substructure?.filter { $0.kind == .genericTypeParam } ?? []
        let names = params.compactMap(\.name)
        #expect(names.contains("A"))
        #expect(names.contains("B"))
    }

    // MARK: - Variable members

    @Test("instance variable with explicit type → kind .varInstance with typename")
    func instanceVarExplicitType() {
        let items = build("class Foo { var name: String = \"\" }")
        let member = items.first?.substructure?.first { $0.kind == .varInstance }
        #expect(member?.name == "name")
        #expect(member?.typename == "String")
    }

    @Test("static variable → kind .varStatic")
    func staticVar() {
        let items = build("class Foo { static var count: Int = 0 }")
        let member = items.first?.substructure?.first { $0.kind == .varStatic }
        #expect(member?.name == "count")
        #expect(member?.typename == "Int")
    }

    @Test("class variable → kind .varStatic")
    func classVar() {
        let items = build("class Foo { class var shared: Foo = Foo() }")
        let member = items.first?.substructure?.first { $0.kind == .varStatic }
        #expect(member?.name == "shared")
    }

    @Test("variable with inferred type and no typenameMap → typename is nil")
    func inferredTypeNoMap() {
        let items = build("class Foo { var x = 42 }")
        let member = items.first?.substructure?.first { $0.kind == .varInstance }
        #expect(member?.name == "x")
        #expect(member?.typename == nil)
    }

    @Test("variable with inferred type resolved via typenameMap")
    func inferredTypeFromMap() {
        let source = "class Foo { var x = 42 }"
        let sourceFile = Parser.parse(source: source)
        let builder = SyntaxStructureBuilder(viewMode: .sourceAccurate, typenameMap: ["Foo.x": "Int"])
        builder.walk(sourceFile)
        let member = builder.topLevelItems.first?.substructure?.first { $0.kind == .varInstance }
        #expect(member?.typename == "Int")
    }

    @Test("optional variable type preserved")
    func optionalType() {
        let items = build("class Foo { var delegate: MyDelegate? }")
        let member = items.first?.substructure?.first { $0.kind == .varInstance }
        #expect(member?.typename == "MyDelegate?")
    }

    // MARK: - Method members

    @Test("instance method → kind .functionMethodInstance")
    func instanceMethod() {
        let items = build("class Foo { func greet() {} }")
        let member = items.first?.substructure?.first { $0.kind == .functionMethodInstance }
        #expect(member?.name == "greet")
    }

    @Test("static method → kind .functionMethodStatic")
    func staticMethod() {
        let items = build("class Foo { static func create() -> Foo { Foo() } }")
        let member = items.first?.substructure?.first { $0.kind == .functionMethodStatic }
        #expect(member?.name == "create")
    }

    @Test("class method → kind .functionMethodStatic")
    func classMethod() {
        let items = build("class Foo { class func make() -> Foo { Foo() } }")
        let member = items.first?.substructure?.first { $0.kind == .functionMethodStatic }
        #expect(member?.name == "make")
    }

    @Test("async method → typename contains 'async'")
    func asyncMethod() {
        let items = build("class Svc { func fetch() async {} }")
        let member = items.first?.substructure?.first { $0.kind == .functionMethodInstance }
        #expect(member?.typename?.contains("async") == true)
    }

    @Test("throws method → typename contains 'throws'")
    func throwsMethod() {
        let items = build("class Svc { func load() throws {} }")
        let member = items.first?.substructure?.first { $0.kind == .functionMethodInstance }
        #expect(member?.typename?.contains("throws") == true)
    }

    @Test("async throws method → typename is 'async throws'")
    func asyncThrowsMethod() {
        let items = build("class Svc { func save() async throws {} }")
        let member = items.first?.substructure?.first { $0.kind == .functionMethodInstance }
        #expect(member?.typename == "async throws")
    }

    @Test("plain method → typename is nil")
    func plainMethodNoTypename() {
        let items = build("class Foo { func sync() {} }")
        let member = items.first?.substructure?.first { $0.kind == .functionMethodInstance }
        #expect(member?.typename == nil)
    }

    // MARK: - init / deinit

    @Test("init method → kind .functionConstructor with name 'init'")
    func initMethod() {
        let items = build("class Foo { init() {} }")
        let member = items.first?.substructure?.first { $0.kind == .functionConstructor }
        #expect(member?.name == "init")
    }

    @Test("deinit → kind .functionDestructor with name 'deinit'")
    func deinitMethod() {
        let items = build("class Foo { deinit {} }")
        let member = items.first?.substructure?.first { $0.kind == .functionDestructor }
        #expect(member?.name == "deinit")
    }

    // MARK: - Enum cases

    @Test("single enum case → .enumcase wrapping .enumelement")
    func singleEnumCase() {
        let items = build("enum Color { case red }")
        let enumCase = items.first?.substructure?.first { $0.kind == .enumcase }
        #expect(enumCase != nil)
        let element = enumCase?.substructure?.first { $0.kind == .enumelement }
        #expect(element?.name == "red")
    }

    @Test("multiple enum cases in one declaration → one .enumcase with multiple .enumelement children")
    func multipleEnumCasesInOneDecl() {
        let items = build("enum Direction { case north, south, east, west }")
        let cases = items.first?.substructure?.filter { $0.kind == .enumcase } ?? []
        #expect(cases.count == 1)
        let elements = cases.first?.substructure?.filter { $0.kind == .enumelement } ?? []
        #expect(elements.count == 4)
    }

    @Test("separate enum case declarations → one .enumcase each")
    func separateEnumCaseDecls() {
        let items = build("enum Suit { case hearts; case diamonds }")
        let cases = items.first?.substructure?.filter { $0.kind == .enumcase } ?? []
        #expect(cases.count == 2)
    }

    // MARK: - Nesting

    @Test("nested class appears in outer class substructure")
    func nestedClassInSubstructure() {
        let items = build("class Outer { class Inner {} }")
        let inner = items.first?.substructure?.first { $0.kind == .class && $0.name == "Inner" }
        #expect(inner != nil)
    }

    @Test("top-level count is 1 for nested types (not flattened by builder)")
    func nestedTypeNotHoisted() {
        let items = build("class Outer { class Inner {} }")
        #expect(items.count == 1)
        #expect(items.first?.name == "Outer")
    }

    @Test("global function outside a type is not captured")
    func globalFunctionIgnored() {
        let items = build("func topLevel() {}")
        #expect(items.isEmpty)
    }

    @Test("global variable outside a type is not captured")
    func globalVariableIgnored() {
        let items = build("var globalX: Int = 0")
        #expect(items.isEmpty)
    }

    // MARK: - Subscripts / body traversal safety

    @Test("subscript body does not leak local vars as members")
    func subscriptBodyNotTraversed() {
        let source = """
        class Foo {
            subscript(i: Int) -> String {
                let local: Int = i
                return "\\(local)"
            }
        }
        """
        let items = build(source)
        let members = items.first?.substructure ?? []
        // subscript itself is skipped; no 'local' variable should appear
        #expect(members.allSatisfy { $0.name != "local" })
    }

    // MARK: - Actor + async/throws integration (limitation fixes)

    @Test("actor with async method → correct kind and effect specifier")
    func actorWithAsyncMethod() {
        let source = """
        actor NetworkManager {
            func fetch(url: URL) async throws -> Data { fatalError() }
        }
        """
        let items = build(source)
        #expect(items.first?.kind == .actor)
        let method = items.first?.substructure?.first { $0.kind == .functionMethodInstance }
        #expect(method?.typename == "async throws")
    }

    @Test("actor kind is .actor, not .class")
    func actorIsNotClass() {
        let items = build("actor MyActor {}")
        #expect(items.first?.kind != .class)
        #expect(items.first?.kind == .actor)
    }

    // MARK: - PlantUML integration (smoke tests)

    @Test("actor produces <<actor>> stereotype in PlantUML output")
    func actorPlantUMLStereotype() {
        let source = "actor ImageCache { var count: Int = 0 }"
        let script = ClassDiagramGenerator().generateScript(for: source)
        #expect(script.text.contains("ImageCache"))
        #expect(script.text.contains("actor"))
    }

    @Test("async method label appears in PlantUML output")
    func asyncMethodInPlantUML() {
        let source = "class Svc { func fetch() async {} }"
        let script = ClassDiagramGenerator().generateScript(for: source)
        #expect(script.text.contains("fetch"))
        #expect(script.text.contains("async"))
    }

    @Test("throws method label appears in PlantUML output")
    func throwsMethodInPlantUML() {
        let source = "class Svc { func load() throws {} }"
        let script = ClassDiagramGenerator().generateScript(for: source)
        #expect(script.text.contains("load"))
        #expect(script.text.contains("throws"))
    }
}
