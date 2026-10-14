import Testing
@testable import SwiftUMLBridgeFramework

@Suite("SyntaxStructure")
struct SyntaxStructureTests {

    // MARK: - find(_:named:)

    @Test("find returns self when name and kind match")
    func findReturnsSelf() {
        let item = SyntaxStructure(kind: .class, name: "Foo")
        let found = item.find(.class, named: "Foo")
        #expect(found === item)
    }

    @Test("find returns nil when kind does not match")
    func findKindMismatch() {
        let item = SyntaxStructure(kind: .class, name: "Foo")
        let found = item.find(.struct, named: "Foo")
        #expect(found == nil)
    }

    @Test("find returns nil when name does not match")
    func findNameMismatch() {
        let item = SyntaxStructure(kind: .class, name: "Bar")
        let found = item.find(.class, named: "Foo")
        #expect(found == nil)
    }

    @Test("find searches substructure recursively")
    func findInSubstructure() {
        let inner = SyntaxStructure(kind: .struct, name: "Inner")
        let outer = SyntaxStructure(kind: .class, name: "Outer", substructure: [inner])
        let found = outer.find(.struct, named: "Inner")
        #expect(found === inner)
    }

    @Test("find returns nil when substructure is empty")
    func findEmptySubstructure() {
        let item = SyntaxStructure(kind: .class, name: "Foo", substructure: [])
        let found = item.find(.struct, named: "Bar")
        #expect(found == nil)
    }

    @Test("find returns nil when no substructure")
    func findNoSubstructure() {
        let item = SyntaxStructure(kind: .class, name: "Foo")
        let found = item.find(.struct, named: "Bar")
        #expect(found == nil)
    }

    // MARK: - fullName and displayName

    @Test("fullName returns name when no parent")
    func fullNameNoParent() {
        let item = SyntaxStructure(kind: .class, name: "MyClass")
        #expect(item.fullName == "MyClass")
    }

    @Test("fullName includes parent name when parent is set")
    func fullNameWithParent() {
        let parent = SyntaxStructure(kind: .class, name: "Outer")
        let child = SyntaxStructure(kind: .struct, name: "Inner")
        child.parent = parent
        #expect(child.fullName == "Outer.Inner")
    }

    @Test("fullName chains multiple ancestors")
    func fullNameWithGrandParent() {
        let grandParent = SyntaxStructure(kind: .class, name: "A")
        let parent = SyntaxStructure(kind: .class, name: "B")
        let child = SyntaxStructure(kind: .struct, name: "C")
        parent.parent = grandParent
        child.parent = parent
        #expect(child.fullName == "A.B.C")
    }

    @Test("fullName returns nil when name is nil")
    func fullNameNilName() {
        let item = SyntaxStructure(kind: .class)
        #expect(item.fullName == nil)
    }

    @Test("displayName returns last component of name")
    func displayNameLastComponent() {
        let item = SyntaxStructure(kind: .struct, name: "Outer.Inner")
        #expect(item.displayName == "Inner")
    }

    @Test("displayName returns name when no dots")
    func displayNameNoDots() {
        let item = SyntaxStructure(kind: .class, name: "MyClass")
        #expect(item.displayName == "MyClass")
    }

    // MARK: - ElementAccessibility comparison

    @Test("open is greater than public")
    func openGreaterThanPublic() {
        #expect(ElementAccessibility.public < ElementAccessibility.open)
    }

    @Test("public is greater than internal")
    func publicGreaterThanInternal() {
        #expect(ElementAccessibility.internal < ElementAccessibility.public)
    }

    @Test("internal is greater than private")
    func internalGreaterThanPrivate() {
        #expect(ElementAccessibility.private < ElementAccessibility.internal)
    }

    @Test("private is greater than fileprivate")
    func privateGreaterThanFileprivate() {
        #expect(ElementAccessibility.fileprivate < ElementAccessibility.private)
    }

    @Test("other is less than fileprivate")
    func otherLessThanFileprivate() {
        #expect(ElementAccessibility.other < ElementAccessibility.fileprivate)
    }

    // MARK: - ElementAccessibility init from AccessLevel

    @Test("ElementAccessibility initializes from AccessLevel.open")
    func accessibilityFromOpen() {
        let ea = ElementAccessibility(orig: .open)
        #expect(ea == .open)
    }

    @Test("ElementAccessibility initializes from AccessLevel.public")
    func accessibilityFromPublic() {
        let ea = ElementAccessibility(orig: .public)
        #expect(ea == .public)
    }

    @Test("ElementAccessibility initializes from AccessLevel.package")
    func accessibilityFromPackage() {
        let ea = ElementAccessibility(orig: .package)
        #expect(ea == .package)
    }

    @Test("ElementAccessibility initializes from AccessLevel.internal")
    func accessibilityFromInternal() {
        let ea = ElementAccessibility(orig: .internal)
        #expect(ea == .internal)
    }

    @Test("ElementAccessibility initializes from AccessLevel.private")
    func accessibilityFromPrivate() {
        let ea = ElementAccessibility(orig: .private)
        #expect(ea == .private)
    }

    @Test("ElementAccessibility initializes from AccessLevel.fileprivate")
    func accessibilityFromFileprivate() {
        let ea = ElementAccessibility(orig: .fileprivate)
        #expect(ea == .fileprivate)
    }

    // MARK: - ElementKind sort ordering

    @Test("protocol sorts before class")
    func protocolSortsBeforeClass() {
        #expect(ElementKind.protocol < ElementKind.class)
    }

    @Test("class sorts before extension")
    func classSortsBeforeExtension() {
        #expect(ElementKind.class < ElementKind.extension)
    }

    @Test("struct sorts before extension")
    func structSortsBeforeExtension() {
        #expect(ElementKind.struct < ElementKind.extension)
    }

    @Test("protocol sorts before extension")
    func protocolSortsBeforeExtension() {
        #expect(ElementKind.protocol < ElementKind.extension)
    }

    // MARK: - Array extensions

    @Test("orderedByProtocolsFirstExtensionsLast puts protocol first")
    func orderedProtocolFirst() {
        let cls = SyntaxStructure(kind: .class, name: "MyClass")
        let proto = SyntaxStructure(kind: .protocol, name: "MyProto")
        let ext = SyntaxStructure(kind: .extension, name: "MyClass")
        let ordered = [ext, cls, proto].orderedByProtocolsFirstExtensionsLast()
        #expect(ordered.first?.kind == .protocol)
        #expect(ordered.last?.kind == .extension)
    }

    @Test("mergeExtensions merges extension members into parent")
    func mergeExtensionsIntoParent() {
        let member = SyntaxStructure(kind: .functionMethodInstance, name: "bar")
        let ext = SyntaxStructure(kind: .extension, name: "Foo", substructure: [member])
        let base = SyntaxStructure(kind: .struct, name: "Foo")
        let merged = [base, ext].mergeExtensions()
        #expect(merged.count == 1)
        #expect(merged.first?.substructure?.count == 1)
    }

    @Test("mergeExtensions does not merge when no parent found")
    func mergeExtensionsNoParent() {
        let member = SyntaxStructure(kind: .functionMethodInstance, name: "bar")
        let ext = SyntaxStructure(kind: .extension, name: "Unknown", substructure: [member])
        let merged = [ext].mergeExtensions()
        #expect(merged.count == 1)
    }

    @Test("populateNestedTypes sets parent reference on nested struct")
    func populateNestedTypesSetsParent() {
        let inner = SyntaxStructure(kind: .struct, name: "Inner")
        let outer = SyntaxStructure(kind: .class, name: "Outer", substructure: [inner])
        let result = [outer].populateNestedTypes()
        let innerFound = result.first(where: { $0.name == "Inner" })
        #expect(innerFound?.parent?.name == "Outer")
    }

    @Test("populateNestedTypes keeps top-level types without parent")
    func populateNestedTypesTopLevelNoParent() {
        let topLevel = SyntaxStructure(kind: .class, name: "TopLevel")
        let result = [topLevel].populateNestedTypes()
        #expect(result.first(where: { $0.name == "TopLevel" })?.parent == nil)
    }

    // MARK: - UnknownCaseRepresentable

    @Test("ElementKind.other is the unknown case")
    func elementKindUnknownCase() {
        let kind = ElementKind(rawValue: "source.lang.swift.decl.unknown.xyz")
        #expect(kind == .other)
    }

    @Test("ElementAccessibility.other is the unknown case")
    func accessibilityUnknownCase() {
        let ea = ElementAccessibility(rawValue: "source.lang.swift.accessibility.unknown")
        #expect(ea == .other)
    }
}
