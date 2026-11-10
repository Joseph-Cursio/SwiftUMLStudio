import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// A subclass has its superclass's nested types and typealiases as members, so after
/// `class Parent { typealias P = R }` and `class Outer: Parent {}`, `Outer.P` means `R`, and so does
/// a bare `P` written in `Outer`. The lookup read only what `Outer`'s body and extensions declare,
/// so `struct W: Outer.P` ended on an undeclared `Outer.P`, or, read without the package, on
/// another directory's `Outer.P` (#250). Each shape builds with swiftc as the issue describes.
@Suite("A member a superclass declares is read through its subclass")
struct InheritedMemberTests {
    /// The issue's writer: `Outer.P` is `Parent.P`, which is `R`.
    private static let main = """
        protocol R {}
        class Parent {
            typealias P = R
        }
        class Outer: Parent {}
        struct W: Outer.P {}
        """
    /// Another target's `Outer`, whose own `P` is `Q`.
    private static let rival = "public enum Outer {\n    public typealias P = Q\n}\npublic protocol Q {}"

    private func svgEdges(_ items: [SyntaxStructure]) -> [String] {
        LayoutGraphBuilder.buildClassDiagram(from: items, configuration: Configuration(format: .svg)).edgeEnds
    }

    private func supertypeLines(_ items: [SyntaxStructure], _ format: DiagramFormat = .plantuml) -> [String] {
        DiagramScript(items: items, configuration: Configuration(format: format)).text
            .split(separator: "\n").map(String.init).filter { $0.contains(" W") && $0.contains("<|") }
    }

    /// With the package read, `Outer` is Main's own class whether or not Main imports the other
    /// target, so `Outer.P` is the `P` it inherits.
    @Test("a dotted name ends on the member its first component's superclass declares", arguments: [false, true])
    func dottedWithPackage(importsRival: Bool) throws {
        let files: [(module: String?, source: String)] = [
            ("Dir0", Self.rival), ("Main", (importsRival ? "import Dir0\n" : "") + Self.main)
        ]
        #expect(svgEdges(try moduleQualifiedItems(files)).filter { $0.hasPrefix("W -> ") } == ["W -> R"])
        #expect(supertypeLines(try moduleQualifiedItems(files)) == ["R <|.. W : conforms to"])
    }

    /// Without the package, the other directory's `Outer.P` is no member of the `Outer` the writer
    /// means, so the inherited one comes first, in every format.
    @Test("a dotted name read without the package ends on the inherited member, not another directory's")
    func dottedWithoutPackage() throws {
        let files: [NearestDirectoryFixture.File] = [
            ("Probe/Sources/Dir0/Outer.swift", Self.rival), ("Probe/Sources/Main/Outer.swift", Self.main)
        ]
        #expect(try NearestDirectoryFixture.edges(files).filter { $0.hasPrefix("W -> ") } == ["W -> R"])
        for format in [DiagramFormat.plantuml, .mermaid] {
            #expect(supertypeLines(try NearestDirectoryFixture.parsed(files), format) == ["R <|.. W : conforms to"])
        }
    }

    /// An inherited nested class is a class's member too: `Outer.Inner` is `Parent.Inner`.
    @Test("an inherited nested class ends its subclass's edge")
    func inheritedNestedClass() throws {
        let source = "class Parent {\n    class Inner {}\n}\nclass Outer: Parent {}\nclass W: Outer.Inner {}\n"
        let items = try moduleQualifiedItems([("Main", source)])
        #expect(svgEdges(items).filter { $0.hasPrefix("W -> ") } == ["W -> Parent.Inner"])
        #expect(supertypeLines(try moduleQualifiedItems([("Main", source)])) == ["Parent.Inner <|-- W : inherits"])
    }

    /// A bare name written in a class sees the members it inherits before any type further out,
    /// so `P` in `Sub` is `Parent.P`, `R`, not the top-level `protocol P`.
    @Test("a bare name in a subclass ends on the member it inherits", arguments: [nil, "Main"] as [String?])
    func bareNameInSubclass(module: String?) throws {
        let source = """
            protocol P {}
            protocol R {}
            class Parent {
                typealias P = R
            }
            class Sub: Parent {
                struct W: P {}
            }
            """
        let items = try moduleQualifiedItems([(module, source)])
        #expect(svgEdges(items).filter { $0.hasPrefix("Sub.W -> ") } == ["Sub.W -> R"])
        let lines = DiagramScript(items: try moduleQualifiedItems([(module, source)]), configuration: Configuration())
            .text.split(separator: "\n").filter { $0.contains("Sub.W") && $0.contains("<|") }
        #expect(lines == ["R <|.. Sub.W : conforms to"])
    }

    /// The writer's member is found however the subclass reaches it: through a superclass's
    /// superclass, one an extension adds to the superclass, a typealias of the subclass as the
    /// first component, a generic superclass, and a superclass written through a typealias.
    @Test("an inherited member is found through each way a class can reach it", arguments: [
        "class Root {\n    typealias P = R\n}\nclass Parent: Root {}\nclass Outer: Parent {}\nstruct W: Outer.P {}",
        "class Parent {}\nextension Parent {\n    typealias P = R\n}\nclass Outer: Parent {}\nstruct W: Outer.P {}",
        "class Parent {\n    typealias P = R\n}\nclass Outer: Parent {}\ntypealias Alias = Outer\nstruct W: Alias.P {}",
        "class Parent<T> {\n    typealias P = R\n}\nclass Outer: Parent<Int> {}\nstruct W: Outer.P {}",
        "class Parent {\n    typealias P = R\n}\ntypealias Base = Parent\nclass Outer: Base {}\nstruct W: Outer.P {}"
    ])
    func eachWayToTheMember(source: String) throws {
        let files: [(module: String?, source: String)] = [("Main", "protocol R {}\n" + source)]
        #expect(svgEdges(try moduleQualifiedItems(files)).filter { $0.hasPrefix("W -> ") } == ["W -> R"])
        #expect(supertypeLines(try moduleQualifiedItems(files)) == ["R <|.. W : conforms to"])
    }

    /// A class's own member comes before one it inherits, whether its body or an extension
    /// declares it.
    @Test("a class's own member comes before an inherited one", arguments: [
        "class Outer: Parent {\n    typealias P = S\n}",
        "class Outer: Parent {}\nextension Outer {\n    typealias P = S\n}"
    ])
    func ownMemberFirst(outer: String) throws {
        let parent = "protocol R {}\nprotocol S {}\nclass Parent {\n    typealias P = R\n}\n"
        let source = parent + outer + "\nstruct W: Outer.P {}"
        let files: [(module: String?, source: String)] = [("Main", source)]
        #expect(svgEdges(try moduleQualifiedItems(files)).filter { $0.hasPrefix("W -> ") } == ["W -> S"])
        #expect(supertypeLines(try moduleQualifiedItems(files)) == ["S <|.. W : conforms to"])
    }

    /// A protocol first in a class's clause is no superclass, so its members are not walked to.
    @Test("a protocol a class conforms to is no superclass")
    func protocolIsNoSuperclass() throws {
        let source = """
            protocol R {}
            class Parent {
                typealias P = R
            }
            class Other: Parent {}
            protocol Proto {}
            class Outer: Proto {}
            struct W: Outer.P {}
            """
        let files: [(module: String?, source: String)] = [("Main", source)]
        #expect(!svgEdges(try moduleQualifiedItems(files)).contains { $0.hasPrefix("W -> ") })
        #expect(supertypeLines(try moduleQualifiedItems(files)) == ["Outer.P <|-- W : inherits"])
    }

    /// A cycle of superclasses, which Swift rejects, ends where the walk comes back to a class.
    @Test("a cycle of superclasses ends")
    func superclassCycleEnds() throws {
        let source = """
            protocol R {}
            class Parent {
                typealias P = R
            }
            class Other: Parent {}
            class First: Second {}
            class Second: First {}
            struct W: First.P {}
            """
        let files: [(module: String?, source: String)] = [("Main", source)]
        #expect(!svgEdges(try moduleQualifiedItems(files)).contains { $0.hasPrefix("W -> ") })
    }

    // MARK: Shapes the review found

    /// A `private` member of a superclass is seen only inside it, never through a subclass, so
    /// the name means what it would with no such member: the top-level `P`, an enclosing type's
    /// `P`, and for a subclass's own `private` one, seen only inside it, the inherited `P`.
    @Test("a private member is not read through a subclass", arguments: [
        ("protocol P {}\nclass Parent {\n    private typealias P = R\n}\n"
            + "class Sub: Parent {\n    struct W: P {}\n}", "Sub.W -> P"),
        ("protocol S {}\nclass Parent {}\nextension Parent {\n    private typealias P = R\n}\n"
            + "enum E {\n    typealias P = S\n    class Sub: Parent {\n        struct W: P {}\n    }\n}",
         "E.Sub.W -> S"),
        ("protocol S {}\nclass Parent {\n    typealias P = R\n}\n"
            + "class Outer: Parent {\n    private typealias P = S\n}\nstruct W: Outer.P {}", "W -> R")
    ])
    func privateMemberIsNotInherited(source: String, edge: String) throws {
        let files: [(module: String?, source: String)] = [("Main", "protocol R {}\n" + source)]
        let writer = String(edge.prefix { $0 != " " })
        #expect(svgEdges(try moduleQualifiedItems(files)).filter { $0.hasPrefix("\(writer) -> ") } == [edge])
    }

    /// When the part before the last dot is itself an inherited member, the last part is that
    /// type's own member: `Outer.Inner.X`, and `Inner.X` written in the subclass, are
    /// `Parent.Inner.X`, read with or without the package.
    @Test("a member of an inherited nested type is read through it", arguments: [nil, "Main"] as [String?])
    func memberOfInheritedType(module: String?) throws {
        let source = """
            protocol R {}
            class Parent {
                class Inner {
                    typealias X = R
                }
            }
            class Outer: Parent {
                struct V: Inner.X {}
            }
            struct W: Outer.Inner.X {}
            """
        let edges = svgEdges(try moduleQualifiedItems([(module, source)]))
        let writers = edges.filter { $0.hasPrefix("W -> ") || $0.hasPrefix("Outer.V -> ") }
        #expect(writers.sorted() == ["Outer.V -> R", "W -> R"])
    }

    /// A class's own member counts however its extension spells the class: through a typealias,
    /// `extension Crate`, it is the member Swift means, and through its module, read without the
    /// package, it may be, so neither is passed over for the inherited one. The lookup does not
    /// read a dotted name through an extension so spelled, so neither edge ends anywhere, as before.
    @Test("a member an extension adds through another spelling of the class is its own")
    func ownMemberThroughOtherSpelling() throws {
        let source = """
            class RBase {}
            class Parent {
                typealias P = RBase
                typealias Q = RBase
            }
            class Outer: Parent {}
            typealias Crate = Outer
            extension Crate {
                class P {
                    func onlyOwn() {}
                }
            }
            extension Main.Outer {
                class Q {}
            }
            class W1: Outer.P {}
            class W2: Outer.Q {}
            """
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: try moduleQualifiedItems([(nil, source)]), configuration: Configuration(format: .svg)
        )
        #expect(graph.owner(of: "onlyOwn") != nil)
        #expect(!graph.edgeEnds.contains("W1 -> RBase"))
        #expect(!graph.edgeEnds.contains("W2 -> RBase"))
    }

    /// With nested types hidden, the inherited member is a type the items do not list: it is what
    /// `Outer.P` means, so the name lands on no other directory's `Outer.P`.
    @Test("a hidden inherited member keeps the name off another directory's type")
    func hiddenInheritedMember() throws {
        let files: [NearestDirectoryFixture.File] = [
            ("Probe/Sources/Dir0/Outer.swift", Self.rival),
            ("Probe/Sources/Main/Outer.swift",
             "class Parent {\n    class P {}\n}\nclass Outer: Parent {}\nclass W: Outer.P {}\n")
        ]
        let hidden = ElementOptions(showNestedTypes: false)
        #expect(!(try NearestDirectoryFixture.edges(files, hidden)).contains("W -> Q"))
        #expect(!(try NearestDirectoryFixture.lines(files, .plantuml, hidden)).contains { $0.hasPrefix("Q <|") })
    }

    /// An inherited typealias of a type outside the diagram that the project extends ends where the
    /// subclass's own such alias does: on that extension's box, in SVG and in the text formats.
    @Test("an inherited alias of an extended outside type ends on its extension", arguments: [false, true])
    func inheritedAliasOfExtendedOutsideType(own: Bool) throws {
        let alias = "    typealias P = CustomStringConvertible\n"
        let source = "class Parent {\n\(own ? "" : alias)}\nclass Outer: Parent {\n\(own ? alias : "")}\n"
            + "struct W: Outer.P {\n    var description: String { \"\" }\n}\n"
            + "extension CustomStringConvertible {\n    func hello() {}\n}\n"
        let files: [(module: String?, source: String)] = [("Main", source)]
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: try moduleQualifiedItems(files), configuration: Configuration(format: .svg)
        )
        let box = try #require(graph.owner(of: "hello"))
        #expect(graph.edgeEnds.filter { $0.hasPrefix("W -> ") } == ["W -> \(box)"])
        #expect(supertypeLines(try moduleQualifiedItems(files)) == ["CustomStringConvertible <|-- W : inherits"])
    }

    /// A `private` member is seen in an extension of its type in the same file however the
    /// extension spells it, and in an extension of a type nested in it.
    @Test("a private member is seen in an extension of its type however spelled", arguments: [
        "class Parent {\n    private typealias P = R\n    class Sub: Parent {}\n}\n"
            + "extension Parent.Sub {\n    struct W: P {}\n}",
        "class Parent {\n    private typealias P = R\n}\ntypealias PA = Parent\nclass Outer: Parent {}\n"
            + "extension PA {\n    struct W: Outer.P {}\n}"
    ])
    func privateMemberSeenInExtension(source: String) throws {
        let files: [(module: String?, source: String)] = [("Main", "protocol P {}\nprotocol R {}\n" + source)]
        let edges = svgEdges(try moduleQualifiedItems(files)).filter { $0.contains(".W -> ") }
        #expect(edges.count == 1 && edges.allSatisfy { $0.hasSuffix(" -> R") }, "\(edges)")
    }

    /// A class declared in an extension of a type outside the diagram has no outermost type of its
    /// own to tell its members by, so neither it nor such a superclass is walked past: its own
    /// member is not passed over for its superclass's, nor a superclass's for one further up.
    @Test("a class in an extension of an outside type keeps its own members", arguments: [
        ("class Base {\n    class X {}\n}\nextension Int {\n    class Sub: Base {\n        class X {}\n    }\n}\n"
            + "class W: Int.Sub.X {}", "W -> Base.X"),
        ("class Root {\n    class Handler {}\n}\n"
            + "extension Int {\n    class Mid: Root {\n        class Handler {}\n    }\n}\n"
            + "class Leaf: Int.Mid {}\nclass H: Leaf.Handler {}", "H -> Root.Handler")
    ])
    func classInOutsideExtension(source: String, wrong: String) throws {
        #expect(!svgEdges(try moduleQualifiedItems([("Main", source)])).contains(wrong))
    }

    /// With modules known, an outside type's extension named like the class, `String.Index`, is
    /// none of the class's, so the member it inherits is still read.
    @Test("an outside type's extension named like the class does not hide what it inherits")
    func outsideExtensionNamedLikeClass() throws {
        let source = """
            protocol R {}
            class Parent {
                typealias P = R
            }
            class Index: Parent {}
            extension String.Index {
                typealias P = Int
            }
            struct W: Index.P {}
            """
        #expect(svgEdges(try moduleQualifiedItems([("Main", source)])).filter { $0.hasPrefix("W -> ") } == ["W -> R"])
    }

    /// The names a superclass may declare are recorded once for each hidden nested type, not again
    /// for every type merged after it: that cost grew with the square of the types.
    @Test("hidden nested types are recorded once each")
    func hiddenNestedTypesCostOnce() throws {
        let source = (0..<3000).map { "struct T\($0) {\n    struct N\($0) {}\n}" }.joined(separator: "\n")
        let items = try #require(SyntaxStructure.create(from: source)?.substructure)
        let configuration = Configuration(elements: ElementOptions(showNestedTypes: false), format: .plantuml)
        let seconds = ThreadCPUClock.seconds { _ = DiagramScript(items: items, configuration: configuration) }
        #expect(seconds < 2, "\(seconds)")
    }
}
