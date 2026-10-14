import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// Which type an SVG class-diagram edge means when several share a name, once some are hidden.
///
/// Drawing only the types the text formats draw (#74) also took hidden types out of the lookup,
/// so a hidden type no longer shadowed its name in its own file and its edges moved to a
/// same-named type elsewhere. A hidden type now still takes its name's lookup: an edge to it ends
/// on an extension whose own lookup finds it, or is dropped. The lookup follows Swift's access
/// control, so a hidden `fileprivate` type never captures a name written in another file.
@Suite("SVG class diagram — name lookup with hidden types")
struct SVGClassDiagramNameLookupTests {

    /// The SVG graph for `files`, each written to its own file, so every declaration has one.
    private func svg(files: [String: String], _ elements: ElementOptions = ElementOptions()) throws -> LayoutGraph? {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SVGClassDiagramNameLookupTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = try files.sorted { $0.key < $1.key }.map { name, source in
            let url = root.appendingPathComponent(name)
            try source.write(to: url, atomically: true, encoding: .utf8)
            return url.path
        }
        return ClassDiagramGenerator()
            .generateScript(for: paths, with: Configuration(elements: elements, format: .svg)).layoutGraph
    }

    private func svg(_ source: String) -> LayoutGraph? {
        ClassDiagramGenerator().generateScript(for: source, with: Configuration(format: .svg)).layoutGraph
    }

    /// A hand-built declaration in `<module>.swift`, in `module`.
    private func declared(
        _ kind: ElementKind, _ name: String, _ module: String, access: ElementAccessibility? = nil,
        inheriting parents: [String] = [], members: [SyntaxStructure]? = nil
    ) -> SyntaxStructure {
        let runMethod = SyntaxStructure(kind: .functionMethodInstance, name: "run")
        let item = SyntaxStructure(
            accessibility: access,
            inheritedTypes: parents.isEmpty ? nil : parents.map { SyntaxStructure(name: $0) },
            kind: kind, name: name,
            substructure: members ?? (kind == .extension ? [runMethod] : nil)
        )
        item.sourceLocation = SourceLocation(filePath: "\(module).swift", line: 1, column: 1)
        item.module = module
        return item
    }

    // MARK: - A Hidden Type Shadows Its Name in Its Own File

    @Test("an edge to a hidden type never moves to a same-named type in another file")
    func hiddenTypeShadowsItsName() throws {
        let withExtension = try svg(files: [
            "A.swift": "fileprivate class Foo {}\nextension Foo { func run() {} }\nclass SubA: Foo {}",
            "B.swift": "class Foo {}\nclass SubB: Foo {}"
        ])
        #expect(withExtension?.nodes.map(\.id) == ["SubA", "Foo", "SubB", "Foo_1"])
        #expect(withExtension?.edgeEnds == ["SubA -> Foo_1", "SubB -> Foo"])

        let withoutExtension = try svg(files: [
            "A.swift": "fileprivate class Foo {}\nclass SubA: Foo {}",
            "B.swift": "class Foo {}\nclass SubB: Foo {}"
        ])
        #expect(withoutExtension?.edgeEnds == ["SubB -> Foo"])
    }

    /// An extension of the other `Foo` is no stand-in: its own lookup finds that `Foo`.
    @Test("an edge to a hidden type never ends on an extension of a same-named type")
    func standInMustExtendTheHiddenType() throws {
        let graph = try svg(files: [
            "A.swift": "fileprivate class Foo {}\nclass SubA: Foo {}",
            "B.swift": "class Foo {}\nextension Foo {}\nclass SubB: Foo {}"
        ])
        #expect(graph?.edgeEnds == ["SubB -> Foo"])
    }

    @Test("a conformance to a hidden protocol never moves to a same-named protocol in another file")
    func hiddenProtocolShadowsItsName() throws {
        let graph = try svg(files: [
            "A.swift": "fileprivate protocol Shape {}\nstruct Circle: Shape {}",
            "B.swift": "protocol Shape {}\nstruct Square: Shape {}"
        ])
        #expect(graph?.edgeEnds == ["Square -> Shape"])
    }

    @Test("a hidden type's nested types never hang off a same-named type in another file")
    func hiddenParentShadowsItsName() throws {
        let graph = try svg(files: [
            "A.swift": "fileprivate struct Outer { struct Inner {} }",
            "B.swift": "struct Outer {}"
        ])
        #expect(graph?.nodes.map(\.id).sorted() == ["Outer", "Outer.Inner"])
        #expect(graph?.edgeEnds == [])
    }

    /// Two `Outer`s in one file: the nested type of the hidden one is dropped, not hung off the
    /// other, though a lookup of the name from that file would find the other first.
    @Test("a hidden parent's nested types never hang off another declaration of its name")
    func hiddenParentIsItsOwnDeclaration() {
        let source = "#if DEBUG\nstruct Outer { struct A {} }\n#else\nfileprivate struct Outer { struct B {} }\n#endif"
        #expect(svg(source)?.edgeEnds == ["Outer -> Outer.A"])
    }

    /// Each extension's nested type hangs off that extension, not the first one.
    @Test("a nested type in a hidden type's extension hangs off that extension")
    func nestedTypeHangsOffItsOwnExtension() {
        let source = "fileprivate struct Foo {}\nextension Foo { struct X {} }\nextension Foo { struct Y {} }"
        #expect(svg(source)?.edgeEnds == ["Foo -> Foo.X", "Foo_1 -> Foo.Y"])
    }

    // MARK: - A Hidden Type Captures No Name It Cannot Be Seen From

    @Test("a name in a third file means the visible type, not another file's fileprivate one", arguments: [
        "fileprivate class Foo {}", "fileprivate class Foo {}\nextension Foo { func run() {} }"
    ])
    func thirdFileSeesTheVisibleType(hiddenFile: String) throws {
        let graph = try svg(files: ["A.swift": hiddenFile, "B.swift": "class Foo {}", "C.swift": "class SubC: Foo {}"])
        let target = try #require(graph?.nodes.first { $0.stereotype == "class" && $0.label == "Foo" })
        #expect(graph?.edgeEnds == ["SubC -> \(target.id)"])
    }

    @Test("a hidden fileprivate protocol never wins a lookup from another file by coming first")
    func hiddenProtocolDoesNotComeFirst() throws {
        let graph = try svg(files: [
            "A.swift": "class Shape {}",
            "B.swift": "fileprivate protocol Shape {}",
            "C.swift": "class Circle: Shape {}"
        ])
        #expect(graph?.edgeEnds == ["Circle -> Shape"])
    }

    /// The extension in C.swift extends the `Foo` it can see, B's, so it stands in for neither.
    @Test("an extension in a third file is no stand-in for another file's fileprivate type", arguments: [
        ("fileprivate class Foo {}\nclass SubA: Foo {}", "class Foo {}", "extension Foo { func run() {} }"),
        ("fileprivate struct Foo { struct Inner {} }", "struct Foo {}", "extension Foo { func run() {} }")
    ])
    func thirdFileExtensionIsNoStandIn(fileA: String, fileB: String, fileC: String) throws {
        let graph = try svg(files: ["A.swift": fileA, "B.swift": fileB, "C.swift": fileC])
        #expect(graph?.edgeEnds == [])
    }

    /// `Foo` in App means Kit's public `Foo`: Core's is internal to Core, and hidden here.
    @Test("a hidden internal type in another module captures no name")
    func hiddenInternalTypeStaysInItsModule() {
        let items = [
            declared(.class, "Foo", "Core", access: .internal),
            declared(.extension, "Foo", "Core"),
            declared(.class, "Foo", "Kit", access: .public),
            declared(.class, "SubC", "App", access: .public, inheriting: ["Foo"])
        ]
        let config = Configuration(elements: ElementOptions(havingAccessLevel: [.open, .public]), format: .svg)
        let graph = LayoutGraphBuilder.buildClassDiagram(from: items, configuration: config)
        #expect(graph.nodes.map { "\($0.id)@\($0.module ?? "")" } == ["Foo@Kit", "SubC@App", "Foo_1@Core"])
        #expect(graph.edgeEnds == ["SubC -> Foo"])
    }

    @Test("a package type is visible from another module of the package")
    func packageTypeCrossesModules() {
        let items = [
            declared(.class, "Foo", "Core", access: .internal),
            declared(.class, "Foo", "Kit", access: .package),
            declared(.class, "SubC", "App", access: .public, inheriting: ["Foo"])
        ]
        let graph = LayoutGraphBuilder.buildClassDiagram(from: items, configuration: Configuration(format: .svg))
        #expect(graph.nodes.map { "\($0.id)@\($0.module ?? "")" } == ["Foo@Core", "Foo_1@Kit", "SubC@App"])
        #expect(graph.edgeEnds == ["SubC -> Foo_1"])
    }

    // MARK: - Drawn File-Scoped Types

    /// The default configuration draws `private` types; one in another file still takes no name.
    @Test("a drawn private type takes no name written in another file", arguments: [
        ("private class Foo {}", ElementOptions()),
        ("fileprivate class Foo {}",
         ElementOptions(havingAccessLevel: [.open, .public, .package, .internal, .private, .fileprivate]))
    ])
    func drawnPrivateTypeStaysInItsFile(fileA: String, elements: ElementOptions) throws {
        let files = ["A.swift": fileA, "B.swift": "class Foo {}", "C.swift": "class SubC: Foo {}"]
        let graph = try svg(files: files, elements)
        #expect(graph?.nodes.map(\.id) == ["Foo", "Foo_1", "SubC"])
        #expect(graph?.edgeEnds == ["SubC -> Foo_1"])
    }

    @Test("a name no visible type takes is dropped, not handed to a hidden type's extension")
    func invisibleTypesLeaveNoFallback() throws {
        let graph = try svg(files: [
            "A.swift": "fileprivate class Operation {}\nextension Operation { func run() {} }",
            "C.swift": "class MyOp: Operation {}"
        ])
        #expect(graph?.edgeEnds == [])
    }

    // MARK: - Access of Enclosing Declarations

    /// A type nested in a `fileprivate` type is no more visible than it, however deep.
    @Test("a nested type takes the access of every type enclosing it", arguments: [
        ("fileprivate struct Outer { class Inner {} }", "struct Outer { class Inner {} }", "Outer.Inner"),
        ("fileprivate struct Outer { struct Mid { class Inner {} } }", "struct Outer { struct Mid { class Inner {} } }",
         "Outer.Mid.Inner")
    ])
    func nestedTypeTakesEnclosingAccess(fileA: String, fileB: String, name: String) throws {
        let graph = try svg(files: ["A.swift": fileA, "B.swift": fileB, "C.swift": "class Sub: \(name) {}"])
        let edge = try #require(graph?.edgeEnds.first { $0.hasPrefix("Sub -> ") })
        #expect(edge == "Sub -> \(name)_1")
    }

    /// `private extension` caps what it holds, and so does the extended type's own access.
    @Test("a type nested in an extension takes the access of the extension and the extended type", arguments: [
        "public struct Foo {}\nprivate extension Foo { class X {} }",
        "public struct Foo {}\nfileprivate extension Foo { class X {} }",
        "public struct Foo {}\npublic extension Foo { fileprivate class X {} }",
        "fileprivate struct Foo {}\nextension Foo { class X {} }"
    ])
    func extensionNestedTypeTakesExtensionAccess(fileA: String) throws {
        let publicOnly = ElementOptions(havingAccessLevel: [.open, .public])
        let graph = try svg(files: [
            "A.swift": fileA,
            "B.swift": "public struct Foo { open class X {} }",
            "C.swift": "public class SubC: Foo.X {}"
        ], publicOnly)
        let visibleX = try #require(graph?.nodes.first { $0.label == "X" && $0.stereotype == "class" })
        #expect(graph?.edgeEnds.contains("SubC -> \(visibleX.id)") == true)
    }

    /// `public extension` makes what it holds public by default, so another module can see it.
    @Test("a type nested in a public extension is visible from another module")
    func publicExtensionRaisesItsMembers() {
        let nested = SyntaxStructure(accessibility: .internal, kind: .class, name: "X")
        nested.sourceLocation = SourceLocation(filePath: "Core.swift", line: 2, column: 1)
        nested.module = "Core"
        let items = [
            declared(.struct, "Foo", "Core", access: .public),
            declared(.extension, "Foo", "Core", access: .public, members: [nested]),
            declared(.class, "Sub", "App", access: .public, inheriting: ["Foo.X"])
        ]
        let graph = LayoutGraphBuilder.buildClassDiagram(from: items, configuration: Configuration(format: .svg))
        #expect(graph.edgeEnds.contains("Sub -> Foo.X"))
    }

    /// So do `package extension`, and a member nested deeper in it, which keeps its own level.
    @Test("a package extension sets its members' default, deeper members keep their own", arguments: [
        (ElementAccessibility.package, ElementAccessibility?.none, "Foo.X"),
        (ElementAccessibility.public, ElementAccessibility.public, "Foo.X.Y")
    ])
    func extensionDefaultReachesItsDirectMembers(
        modifier: ElementAccessibility, deeper: ElementAccessibility?, name: String
    ) {
        let member = SyntaxStructure(accessibility: .internal, kind: .class, name: "X")
        member.sourceLocation = SourceLocation(filePath: "Core.swift", line: 2, column: 1)
        member.module = "Core"
        if let deeper {
            let nested = SyntaxStructure(accessibility: deeper, kind: .class, name: "Y")
            nested.sourceLocation = SourceLocation(filePath: "Core.swift", line: 3, column: 1)
            nested.module = "Core"
            member.substructure = [nested]
        }
        let items = [
            declared(.struct, "Foo", "Core", access: .public),
            declared(.extension, "Foo", "Core", access: modifier, members: [member]),
            declared(.class, "Sub", "App", access: .public, inheriting: [name])
        ]
        let graph = LayoutGraphBuilder.buildClassDiagram(from: items, configuration: Configuration(format: .svg))
        #expect(graph.edgeEnds.contains("Sub -> \(name)"))
    }

    /// `extension Outer.Inner` holds `X`; `Inner` is nested in an extension of a `fileprivate`
    /// `Outer`, so X is file-scoped through two extensions.
    @Test("the extended type's access caps through extensions of extensions")
    func extendedTypeCapRecurses() throws {
        let graph = try svg(files: [
            "A.swift": "fileprivate struct Outer {}\nextension Outer { struct Inner {} }\n"
                + "extension Outer.Inner { class X {} }",
            "B.swift": "struct Outer { struct Inner { class X {} } }",
            "C.swift": "class Sub: Outer.Inner.X {}"
        ])
        let visibleX = try #require(graph?.nodes.first {
            $0.label == "X" && $0.sourceLocation?.filePath.hasSuffix("/B.swift") == true
        })
        #expect(graph?.edgeEnds.filter { $0.hasPrefix("Sub -> ") } == ["Sub -> \(visibleX.id)"])
    }

    // MARK: - Names of Types Outside the Diagram

    /// `Operation` in B.swift is a type outside the diagram, as A's is `fileprivate`; B's own
    /// extension extends that same type and stands in for it, wherever the extension is.
    @Test("an edge to a type outside the diagram ends on an extension of that same type", arguments: [
        ("fileprivate class Operation {}", "B.swift"),
        ("private class Operation {}", "B.swift"),
        ("fileprivate class Operation {}", "C.swift")
    ])
    func outsideTypeEndsOnItsExtension(fileA: String, extensionFile: String) throws {
        var files = ["A.swift": fileA, "B.swift": "class MyOp: Operation {}"]
        files[extensionFile, default: ""] += "\nextension Operation { func run() {} }"
        let graph = try svg(files: files)
        let standIn = try #require(graph?.nodes.first {
            $0.stereotype == "extension" && $0.sourceLocation?.filePath.hasSuffix("/\(extensionFile)") == true
        })
        #expect(graph?.edgeEnds.contains("MyOp -> \(standIn.id)") == true)
    }
}
