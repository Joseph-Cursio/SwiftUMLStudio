import Testing
@testable import SwiftUMLBridgeFramework

/// PlantUML, Mermaid and Nomnoml wrote a supertype edge's end as the supertype's name, so when
/// two boxes shared it the edge reached the first, while SVG ends it on the type the name means
/// where it is written (`DrawnEdgeEnds`): by file, module and access, or a hidden type's
/// stand-in. Now the text formats end it on that same element's alias. Every source passes
/// `swiftc -typecheck`, its files together, with a member only the intended supertype has.
@Suite("Text formats end a supertype edge where SVG does")
struct SupertypeEdgeEndTests {

    static let textFormats: [DiagramFormat] = [.plantuml, .mermaid, .nomnoml]
    static let everyAccessLevel: [AccessLevel] = [.open, .public, .package, .internal, .fileprivate, .private]

    /// The items of `files`, each stamped as declared in its own file, as on disk.
    private func parsed(_ files: [(name: String, source: String)]) throws -> [SyntaxStructure] {
        try files.flatMap { file in
            let items = try #require(SyntaxStructure.create(from: file.source)?.substructure)
            func stamp(_ item: SyntaxStructure) {
                item.sourceLocation = SourceLocation(filePath: file.name, line: 1, column: 1)
                item.substructure?.forEach(stamp)
            }
            items.forEach(stamp)
            return items
        }
    }

    private func script(
        _ files: [(name: String, source: String)], _ format: DiagramFormat,
        _ mode: ExtensionVisualization = .all, access: [AccessLevel] = ElementOptions.defaultAccessLevels
    ) throws -> DiagramScript {
        let elements = ElementOptions(havingAccessLevel: access, showExtensions: mode)
        return DiagramScript(items: try parsed(files), configuration: Configuration(elements: elements, format: format))
    }

    /// Each supertype edge drawn from `child`, as `end arrow`: `P <|--`, `P <|..`, or Nomnoml's
    /// `P -:>` and `P --:>`.
    private func edges(
        from child: String, _ files: [(name: String, source: String)], _ format: DiagramFormat,
        _ mode: ExtensionVisualization = .all, access: [AccessLevel] = ElementOptions.defaultAccessLevels
    ) throws -> [String] {
        let text = try script(files, format, mode, access: access).text
        return text.split(separator: "\n").compactMap { line -> String? in
            if format == .nomnoml {
                // `[child] -:> label [parent]`
                let words = line.split(separator: " ")
                guard words.first == "[\(child)]", words.count >= 3, let last = words.last else { return nil }
                return "\(last.dropFirst().dropLast()) \(words[1])"
            }
            // `parent <|-- child : label`
            let words = line.split(separator: " ")
            guard words.count >= 3, ["<|--", "<|.."].contains(words[1]), words[2] == child else { return nil }
            return "\(words[0]) \(words[1])"
        }
    }

    /// The members of the SVG node each supertype edge from `child` ends on, which tells the
    /// boxes that share a name apart.
    private func svgEndMembers(
        from child: String, _ files: [(name: String, source: String)], _ mode: ExtensionVisualization = .all,
        access: [AccessLevel] = ElementOptions.defaultAccessLevels
    ) throws -> [[String]] {
        let graph = try script(files, .svg, mode, access: access).layoutGraph
        let ends = graph?.edges.filter { $0.sourceId == child && $0.style != .composition }.map(\.targetId) ?? []
        return ends.map { end in graph?.nodes.first { $0.id == end }?.compartments.flatMap(\.items) ?? [] }
    }

    // MARK: - A hidden type's stand-in

    /// Both types are hidden, and each one's extension stands in for it (#153). `U` conforms to
    /// the protocol, so its edge ends on the protocol's stand-in, the second box named `P`.
    static let standIns: [(name: String, source: String)] = [
        ("B.swift", "fileprivate struct P {}\nextension P { func fromStructFile() {} }"),
        ("C.swift", "fileprivate protocol P {}\nextension P { func fromProtocolFile() {} }\nstruct U: P {}")
    ]

    @Test("an edge to a hidden protocol ends on its stand-in, not another hidden type's",
          arguments: textFormats, [ExtensionVisualization.all, .merged])
    func endsOnHiddenTypesStandIn(format: DiagramFormat, mode: ExtensionVisualization) throws {
        let arrow = format == .nomnoml ? "-:>" : "<|--"
        #expect(try edges(from: "U", Self.standIns, format, mode) == ["P0 \(arrow)"])
        #expect(try svgEndMembers(from: "U", Self.standIns, mode) == [["~ fromProtocolFile()"]])
    }

    /// The access levels hide the internal protocol. Its stand-in is the bare extension, not
    /// `extension Int?`, which extends Swift's `Optional` (#126).
    @Test("an edge to a hidden protocol ends on its stand-in, not a sugared extension of the same name",
          arguments: textFormats, [ExtensionVisualization.all, .merged])
    func endsOnStandInNotSugaredExtension(format: DiagramFormat, mode: ExtensionVisualization) throws {
        let files = [("A.swift", """
            protocol Optional {}
            extension Int? { func sugared() {} }
            extension Optional { func bare() {} }
            public struct U: Optional {}
            """)]
        let arrow = format == .nomnoml ? "-:>" : "<|--"
        #expect(try edges(from: "U", files, format, mode, access: [.public, .open]) == ["Optional0 \(arrow)"])
        #expect(try svgEndMembers(from: "U", files, mode, access: [.public, .open]) == [["~ bare()"]])
    }

    // MARK: - Same-named types in different files

    static let twoFiles: [(name: String, source: String)] = [
        ("A.swift", "fileprivate class Base { var inA = 0 }\nfileprivate class SubA: Base {}"),
        ("B.swift", "fileprivate class Base { var inB = 0 }\nfileprivate class SubB: Base {}")
    ]

    @Test("an edge ends on the supertype in its own file, not the first of its name", arguments: textFormats)
    func endsOnOwnFilesType(format: DiagramFormat) throws {
        let arrow = format == .nomnoml ? "-:>" : "<|--"
        #expect(try edges(from: "SubA", Self.twoFiles, format, access: Self.everyAccessLevel) == ["Base \(arrow)"])
        #expect(try edges(from: "SubB", Self.twoFiles, format, access: Self.everyAccessLevel) == ["Base0 \(arrow)"])
        #expect(try svgEndMembers(from: "SubB", Self.twoFiles, access: Self.everyAccessLevel) == [["~ inB"]])
    }

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
        #expect(try edges(from: "Sub", files, format, access: Self.everyAccessLevel) == ["Base0 \(inherits)"])
        #expect(try edges(from: "Conformer", files, format, access: Self.everyAccessLevel) == ["Base \(realizes)"])
    }

    // MARK: - Two types recorded under one name (#126)

    /// `Array.Base` is both a `Base` nested in a project `struct Array` and one declared in
    /// `extension [Int]`.
    @Test("an edge ends on the Array.Base the name means", arguments: textFormats)
    func endsOnTheArrayBaseTheNameMeans(format: DiagramFormat) throws {
        let arrow = format == .nomnoml ? "-:>" : "<|--"
        // In the extension, `Base` is its own: the second `Array.Base`.
        let inExtension = [("A.swift", """
            struct Array { class Base { var local = 0 } }
            extension [Int] {
                class Base { var sugar = 0 }
                class Sub: Base {}
            }
            """)]
        #expect(try edges(from: "Array.Sub", inExtension, format) == ["Array.Base0 \(arrow)"])
        #expect(try svgEndMembers(from: "Array.Sub", inExtension) == [["~ sugar"]])
        // Written `Array.Base`, it is the project's, declared second.
        let written = [("A.swift", """
            extension [Int] { class Base { var sugar = 0 } }
            struct Array { class Base { var local = 0 } }
            class Sub: Array.Base {}
            """)]
        #expect(try edges(from: "Sub", written, format) == ["Array.Base0 \(arrow)"])
        #expect(try svgEndMembers(from: "Sub", written) == [["~ local"]])
    }

    // MARK: - No drawn end

    /// `U`'s `P` is C's hidden protocol, which has no stand-in, so SVG draws no edge. Written by
    /// name, the edge would end on B's `extension P`, another hidden type's stand-in.
    static let noStandIn: [(name: String, source: String)] = [
        ("B.swift", "fileprivate struct P {}\nextension P { func fromStructFile() {} }"),
        ("C.swift", "fileprivate protocol P {}\nstruct U: P {}")
    ]

    @Test("an edge SVG finds no end for is left out where a drawn box has its name",
          arguments: textFormats, [ExtensionVisualization.all, .merged])
    func noEndBesideABoxOfItsName(format: DiagramFormat, mode: ExtensionVisualization) throws {
        #expect(try edges(from: "U", Self.noStandIn, format, mode) == [])
        #expect(try svgEndMembers(from: "U", Self.noStandIn, mode) == [])
        // Swift's `Optional` here only shares the hidden protocol's name.
        let sugared = [("A.swift", """
            protocol Optional {}
            extension Int? { func sugared() {} }
            public struct U: Optional {}
            """)]
        #expect(try edges(from: "U", sugared, format, mode, access: [.public, .open]) == [])
        // A `private` protocol in another file is drawn; B's own is hidden, and has no stand-in.
        let otherFile = [
            ("A.swift", "private protocol Drawable { func draw() }\n"
                + "private struct Circle: Drawable { func draw() {} }"),
            ("B.swift", "fileprivate protocol Drawable { func render() }\nstruct Square: Drawable { func render() {} }")
        ]
        let realizes = format == .nomnoml ? "--:>" : "<|.."
        #expect(try edges(from: "Square", otherFile, format, mode) == [])
        #expect(try edges(from: "Circle", otherFile, format, mode) == ["Drawable \(realizes)"])
    }

    /// Swift's `Identifiable`, which another file's `fileprivate protocol Identifiable` only
    /// shares a name with.
    @Test("an edge to a type outside the diagram is left out where a drawn box has its name", arguments: textFormats)
    func outsideTypeBesideABoxOfItsName(format: DiagramFormat) throws {
        let files = [
            ("X.swift", "fileprivate protocol Identifiable { func own() }"),
            ("Y.swift", "struct User: Identifiable { var id: Int }")
        ]
        #expect(try edges(from: "User", files, format, access: Self.everyAccessLevel) == [])
        #expect(try svgEndMembers(from: "User", files, access: Self.everyAccessLevel) == [])
    }

    /// With extensions hidden, no box is named `P`, so the edge is written to a node of its own,
    /// as it always has been.
    @Test("an edge SVG finds no end for is still written by name where no drawn box has it", arguments: textFormats)
    func noEndWrittenByName(format: DiagramFormat) throws {
        let arrow = format == .nomnoml ? "-:>" : "<|--"
        #expect(try edges(from: "U", Self.noStandIn, format, .none) == ["P \(arrow)"])
    }

    // MARK: - Repeats

    /// Each file's extension conforms to its own `fileprivate protocol P`, so `Foo`'s box draws an
    /// edge to each, as SVG does (#76). They share a name, which used to drop the second.
    @Test("a merged extension's conformance to another file's protocol of its name is drawn", arguments: textFormats)
    func mergedConformanceToAnotherFilesProtocol(format: DiagramFormat) throws {
        let files = [
            ("A.swift", "fileprivate protocol P { func fromA() }\nstruct Foo: P { func fromA() {} }"),
            ("B.swift", "fileprivate protocol P { func fromB() }\nextension Foo: P { func fromB() {} }")
        ]
        let realizes = format == .nomnoml ? "--:>" : "<|.."
        #expect(try edges(from: "Foo", files, format, .merged, access: Self.everyAccessLevel)
            == ["P \(realizes)", "P0 \(realizes)"])
        #expect(try svgEndMembers(from: "Foo", files, .merged, access: Self.everyAccessLevel)
            == [["~ fromA()"], ["~ fromB()"]])
    }

    /// Both `#if` clauses conform `Foo` to `P`, one through an alias, so its box draws one edge.
    @Test("a merged conformance repeated through a typealias is drawn once", arguments: textFormats)
    func mergedConformanceRepeatedThroughAlias(format: DiagramFormat) throws {
        let files = [("A.swift", """
            protocol P {}
            typealias Q = P
            struct Foo {}
            #if DEBUG
            extension Foo: P {}
            #else
            extension Foo: Q {}
            #endif
            """)]
        let realizes = format == .nomnoml ? "--:>" : "<|.."
        #expect(try edges(from: "Foo", files, format, .merged) == ["P \(realizes)"])
    }

    // MARK: - Labels

    /// Protocols are drawn first, in file order, so `Named` had no box yet when `Animal`'s edge to
    /// it was drawn, and the edge was labelled `inherits`.
    @Test("an edge to a parent protocol drawn later is labelled as a conformance", arguments: textFormats)
    func parentProtocolDrawnLater(format: DiagramFormat) throws {
        let text = try script([("A.swift", "protocol Animal: Named {}\nprotocol Named {}")], format).text
        let edge = format == .nomnoml ? "[Animal] --:> conforms to [Named]" : "Named <|.. Animal : conforms to"
        #expect(text.split(separator: "\n").contains { $0.hasPrefix(edge) })
    }

    // MARK: - Controls

    @Test("a superclass declared after its subclass is still its edge's end", arguments: textFormats)
    func superclassDeclaredLater(format: DiagramFormat) throws {
        let arrow = format == .nomnoml ? "-:>" : "<|--"
        #expect(try edges(from: "Sub", [("A.swift", "class Sub: Base {}\nclass Base {}")], format) == ["Base \(arrow)"])
    }

    @Test("a type outside the diagram is still written by name", arguments: textFormats)
    func outsideTypeWrittenByName(format: DiagramFormat) throws {
        let files = [("A.swift", "protocol P {}\nstruct Foo: P, Codable {}")]
        let (inherits, realizes) = format == .nomnoml ? ("-:>", "--:>") : ("<|--", "<|..")
        #expect(try edges(from: "Foo", files, format) == ["P \(realizes)", "Codable \(inherits)"])
    }
}
