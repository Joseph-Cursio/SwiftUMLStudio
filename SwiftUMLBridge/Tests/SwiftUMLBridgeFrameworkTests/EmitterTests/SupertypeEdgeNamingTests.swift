import Testing
@testable import SwiftUMLBridgeFramework

/// Which relationship PlantUML, Mermaid and Nomnoml name a supertype edge with: `conforms to`,
/// with the realization arrow, when the name means a protocol the sources declare, drawn or
/// hidden, and `inherits`, with the arrow of the declaration the edge starts at, for anything
/// else. It used to follow the first box of the name drawn so far, which could be another file's
/// type, an extension, or none. Every source passes `swiftc -typecheck`, its files together.
@Suite("Text formats name a supertype edge after the type its name means")
struct SupertypeEdgeNamingTests {

    static let textFormats: [DiagramFormat] = [.plantuml, .mermaid, .nomnoml]
    static let everyAccessLevel: [AccessLevel] = [.open, .public, .package, .internal, .fileprivate, .private]

    // MARK: - Arrows

    /// The protocol is drawn first, so the name `Base` was a protocol's, and `Sub`'s edge to its
    /// superclass took the realization arrow. It is an inheritance, to the class.
    @Test("an edge to a class takes the inheritance arrow though a protocol of its name comes first",
          arguments: textFormats)
    func classEndTakesInheritanceArrow(format: DiagramFormat) throws {
        let files = [
            ("A.swift", "fileprivate protocol Base {}\nfileprivate struct Conformer: Base {}"),
            ("B.swift", "fileprivate class Base { var isClass = 0 }\nfileprivate class Sub: Base {}")
        ]
        let (inherits, realizes) = format == .nomnoml ? ("-:>", "--:>") : ("<|--", "<|..")
        #expect(try supertypeEdges(from: "Sub", files, format, access: Self.everyAccessLevel) == ["Base0 \(inherits)"])
        #expect(
            try supertypeEdges(from: "Conformer", files, format, access: Self.everyAccessLevel) == ["Base \(realizes)"]
        )
    }

    // MARK: - Labels

    /// Protocols are drawn first, in file order, so `Named` had no box yet when `Animal`'s edge to
    /// it was drawn, and the edge was labelled `inherits`.
    @Test("an edge to a parent protocol drawn later is labelled as a conformance", arguments: textFormats)
    func parentProtocolDrawnLater(format: DiagramFormat) throws {
        let text = try classDiagram([("A.swift", "protocol Animal: Named {}\nprotocol Named {}")], format).text
        let edge = format == .nomnoml ? "[Animal] --:> conforms to [Named]" : "Named <|.. Animal : conforms to"
        #expect(text.split(separator: "\n").contains { $0.hasPrefix(edge) })
    }

    /// B's `U` conforms to B's hidden protocol `P`, whose stand-in is B's `extension P`. The
    /// edge was named as the first drawn box named `P` is: A's `private` type, a protocol or a
    /// class, or with no A.swift no box at all, which named it `inherits`.
    @Test("an edge to a hidden protocol's stand-in is a conformance, whatever else shares its name",
          arguments: textFormats,
          ["private protocol P { func onlyInA() }", "private class P { func onlyInA() {} }", nil])
    func standInEdgeNamedAfterHiddenProtocol(format: DiagramFormat, other: String?) throws {
        let own = ("B.swift", "fileprivate protocol P { func onlyInB() }\nextension P { func helper() {} }\n"
            + "struct U: P { func onlyInB() {} }")
        let files = (other.map { [("A.swift", $0)] } ?? []) + [own]
        let end = other == nil ? "P" : "P0"
        let edge = format == .nomnoml ? "[U] --:> conforms to [\(end)]" : "\(end) <|.. U : conforms to"
        #expect(try classDiagram(files, format).text.split(separator: "\n").contains { $0.hasPrefix(edge) })
    }

    /// The mirror: an edge to a hidden class's stand-in inherits, though a `private protocol`
    /// of its name, drawn first, used to make it a conformance.
    @Test("an edge to a hidden class's stand-in is an inheritance beside a protocol of its name",
          arguments: textFormats)
    func standInEdgeNamedAfterHiddenClass(format: DiagramFormat) throws {
        let files = [
            ("A.swift", "private protocol Base {}"),
            ("B.swift", "fileprivate class Base { var isClass = 0 }\nextension Base { func helper() {} }\n"
                + "private class Sub: Base { func f() -> Int { isClass } }")
        ]
        let edge = format == .nomnoml ? "[Sub] -:> inherits [Base0]" : "Base0 <|-- Sub : inherits"
        #expect(try classDiagram(files, format).text.split(separator: "\n").contains { $0.hasPrefix(edge) })
    }

    /// Every edge line `format` writes for `files`, whole, so `<..`, `--` and `-` show too.
    private func edgeLines(
        _ files: [(name: String, source: String)], _ format: DiagramFormat, _ mode: ExtensionVisualization = .all,
        access: [AccessLevel] = ElementOptions.defaultAccessLevels
    ) throws -> [String] {
        try classDiagram(files, format, mode, access: access).text.split(separator: "\n").map(String.init)
    }

    /// The edge from `child` to `parent` as each format writes it: PlantUML and Mermaid
    /// `parent arrow child : label`, Nomnoml `[child] arrow label [parent]`.
    private func edgeLine(_ format: DiagramFormat, _ parent: String, _ arrow: (text: String, nomnoml: String),
                          _ child: String, _ label: String) -> String {
        format == .nomnoml
            ? "[\(child)] \(arrow.nomnoml) \(label) [\(parent)]" : "\(parent) \(arrow.text) \(child) : \(label)"
    }

    static let realizes = (text: "<|..", nomnoml: "--:>")
    static let inherits = (text: "<|--", nomnoml: "-:>")

    /// A conformance to a hidden protocol is one from every kind of declaration, an extension's
    /// box included, whose own arrow would otherwise be `<..`, and an enum's or actor's, `--`.
    @Test("every kind of declaration's edge to a hidden protocol is a conformance",
          arguments: textFormats, [ExtensionVisualization.all, .merged])
    func everyKindConformsToHiddenProtocol(format: DiagramFormat, mode: ExtensionVisualization) throws {
        let files = [("A.swift", """
            fileprivate protocol P { func onlyP() }
            extension P { func helper() {} }
            struct Foo {}
            extension Foo: P { func onlyP() {} }
            enum E: P { case a; func onlyP() {} }
            actor Act: P { nonisolated func onlyP() {} }
            """)]
        let lines = try edgeLines(files, format, mode)
        let foo = mode == .merged ? "Foo" : "Foo0"
        for child in [foo, "E", "Act"] {
            #expect(lines.contains(edgeLine(format, "P", Self.realizes, child, "conforms to")), "\(child)")
        }
    }

    @Test("an edge to a hidden protocol through a typealias or a nested name is a conformance", arguments: textFormats)
    func hiddenProtocolThroughAliasOrNesting(format: DiagramFormat) throws {
        let alias = [("A.swift", "fileprivate protocol P { func onlyP() }\nfileprivate typealias Q = P\n"
            + "struct U: Q { func onlyP() {} }")]
        #expect(try edgeLines(alias, format).contains(edgeLine(format, "P", Self.realizes, "U", "conforms to")))
        let nested = [("A.swift", """
            struct Outer {
                fileprivate protocol Inner { func i() }
                private struct Impl: Inner { func i() {} }
            }
            """)]
        #expect(try edgeLines(nested, format)
            .contains(edgeLine(format, "Outer.Inner", Self.realizes, "Outer.Impl", "conforms to")))
    }

    /// An enum's raw type is no conformance, though a `private protocol` of its name is drawn
    /// first; the enum keeps its own arrow.
    @Test("an enum's raw-type edge inherits beside a protocol of its name", arguments: textFormats)
    func rawTypeEdgeInherits(format: DiagramFormat) throws {
        let files = [
            ("A.swift", "private protocol Code { func onlyProto() }"),
            ("B.swift", """
                private struct Code: ExpressibleByStringLiteral, Equatable {
                    let value: String
                    init(stringLiteral value: String) { self.value = value }
                    func onlyStruct() {}
                }
                private enum Kind: Code { case first = "a"; case second = "b" }
                """)
        ]
        let enumArrow = (text: "--", nomnoml: "-")
        #expect(try edgeLines(files, format).contains(edgeLine(format, "Code0", enumArrow, "Kind", "inherits")))
    }

    /// A type outside the diagram has a kind the diagram does not know: its edge inherits, as
    /// the reference has it, never an `ext` label from an extension of it or a protocol of its
    /// name in another file that the writer cannot see.
    @Test("an edge to a type outside the diagram inherits, whatever box shares its name", arguments: textFormats)
    func outsideTypeEdgeInherits(format: DiagramFormat) throws {
        let encodable = [("A.swift", """
            extension Encodable { func encodeHelper() {} }
            struct Foo {}
            extension Foo: Encodable { func use() { encodeHelper() } }
            """)]
        let dependency = (text: "<..", nomnoml: "-->")
        #expect(try edgeLines(encodable, format)
            .contains(edgeLine(format, "Encodable", dependency, "Foo0", "inherits")))
        let nsObject = [
            ("A.swift", "private protocol NSObject { func onlyProto() }"),
            ("B.swift", "import Foundation\nextension NSObject { @objc func helperFromB() {} }\n"
                + "private class V: NSObject { func use() { helperFromB() } }")
        ]
        #expect(try edgeLines(nsObject, format).contains(edgeLine(format, "NSObject0", Self.inherits, "V", "inherits")))
    }
}
