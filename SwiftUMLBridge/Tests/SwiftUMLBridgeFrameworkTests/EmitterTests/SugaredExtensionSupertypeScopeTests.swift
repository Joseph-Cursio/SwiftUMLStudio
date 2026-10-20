import Testing
@testable import SwiftUMLBridgeFramework

/// A type nested in an extension is recorded under the extended type's name, so `Array.Base` is
/// both a `Base` nested in a project `struct Array` and one declared in `extension [Int]`, a member
/// of Swift's `Array`. Inside `extension [Int]`, Swift looks a supertype up among the members of
/// Swift's `Array`, then at the top level, never in the project's `Array`; written as `Array.Base`,
/// it is a member of whatever `Array` means there, the project's unless a nearer one, an
/// enclosing type's `typealias Array = [Int]` say, shadows it. Every source here passes
/// `swiftc -typecheck`, and its `Sub` uses a member only the intended supertype has, so the
/// typecheck proves which one Swift means (#126 follow-up).
@Suite("A supertype named in a sugared extension is looked up in Swift's type")
struct SugaredExtensionSupertypeScopeTests {

    static let formats: [DiagramFormat] = [.plantuml, .mermaid, .nomnoml, .svg]
    static let modes: [ExtensionVisualization] = [.all, .merged, .none]

    private func script(
        _ source: String, _ format: DiagramFormat, _ mode: ExtensionVisualization = .all,
        relationships: RelationshipOptions = RelationshipOptions()
    ) -> DiagramScript {
        let elements = ElementOptions(showExtensions: mode)
        let configuration = Configuration(elements: elements, relationships: relationships, format: format)
        return ClassDiagramGenerator().generateScript(for: source, with: configuration)
    }

    /// The ids the supertype edges drawn from `child` end on, in drawing order.
    private func ends(
        from child: String, _ source: String, _ format: DiagramFormat, _ mode: ExtensionVisualization = .all,
        relationships: RelationshipOptions = RelationshipOptions()
    ) -> [String] {
        let drawn = script(source, format, mode, relationships: relationships)
        switch format {
        case .svg:
            return drawn.layoutGraph?.edges
                .filter { $0.sourceId == child && $0.style != .composition }.map(\.targetId) ?? []
        case .nomnoml:
            // `[child] -:> label [parent]`; a nesting edge starts at the parent.
            return drawn.text.split(separator: "\n").compactMap { line -> String? in
                guard line.hasPrefix("[\(child)] -"), let open = line.lastIndex(of: "[") else { return nil }
                return String(line[line.index(after: open)...].dropLast())
            }
        default:
            // `parent <|-- child : label`.
            return drawn.text.split(separator: "\n").compactMap { line -> String? in
                let words = line.split(separator: " ")
                guard words.count >= 3, words[1] == "<|--", words[2] == child else { return nil }
                return String(words[0])
            }
        }
    }

    /// The members of the SVG node each supertype edge from `child` ends on.
    private func endMembers(from child: String, _ source: String, _ mode: ExtensionVisualization = .all) -> [[String]] {
        let graph = script(source, .svg, mode).layoutGraph
        return ends(from: child, source, .svg, mode).map { end in
            graph?.nodes.first { $0.id == end }?.compartments.flatMap(\.items) ?? []
        }
    }

    /// The SVG node nested in `parent`: the end of the one nesting edge drawn from it.
    private func nested(in parent: String, _ graph: LayoutGraph?) -> String? {
        let ends = graph?.edges.filter { $0.sourceId == parent && $0.style == .composition }.map(\.targetId)
        return ends?.count == 1 ? ends?.first : nil
    }

    // MARK: - A short name

    /// `Base` in `extension [Int]` is the top-level `Base`: Swift's `Array` has no member `Base`.
    @Test("a short name in a sugared extension is not a project Array's member", arguments: formats, modes)
    func shortNameSkipsProjectMember(format: DiagramFormat, mode: ExtensionVisualization) {
        let source = """
            class Base { var top = 0 }
            struct Array { class Base { var local = 0 } }
            extension [Int] { class Sub: Base { func f() -> Int { top } } }
            """
        #expect(ends(from: "Array.Sub", source, format, mode) == ["Base"])
    }

    @Test("a short name a level deeper in a sugared extension is not a project Array's member", arguments: formats)
    func deeperShortNameSkipsProjectMember(format: DiagramFormat) {
        let source = """
            class Base { var top = 0 }
            struct Array { enum Inner { class Base { var local = 0 } } }
            extension [Int] { enum Inner { class Sub: Base { func f() -> Int { top } } } }
            """
        #expect(ends(from: "Array.Inner.Sub", source, format) == ["Base"])
    }

    /// `Stats` is declared in `extension [Int]`, so `extension [Int].Stats` is inside Swift's
    /// `Array` too, though a project `Array` has a `Stats` of its own.
    @Test("a short name in an extension of a sugared member path is not a project Array's member",
          arguments: formats, modes)
    func shortNameInExtensionOfSugaredPath(format: DiagramFormat, mode: ExtensionVisualization) {
        let source = """
            class Base { var top = 0 }
            struct Array { struct Stats { class Base { var local = 0 } } }
            extension [Int] { struct Stats {} }
            extension [Int].Stats { class Sub: Base { func f() -> Int { top } } }
            """
        #expect(ends(from: "Array.Stats.Sub", source, format, mode) == ["Base"])
    }

    @Test("a typealias in a sugared extension aliases the top-level type, not a project Array's member",
          arguments: formats)
    func aliasInSugaredExtension(format: DiagramFormat) {
        let source = """
            class Base { var top = 0 }
            struct Array { class Base { var local = 0 } }
            extension [Int] {
                typealias Alias = Base
                class Sub: Alias { func f() -> Int { top } }
            }
            """
        #expect(ends(from: "Array.Sub", source, format) == ["Base"])
    }

    /// Both aliases are recorded as `Array.Alias`. The text formats write the type an alias comes
    /// to (`TypeAliasResolver.resolve`), so the root `qualifiedName(ofWritten:from:)` works out
    /// decides which alias they follow.
    @Test("a typealias in a sugared extension is its own beside a project Array's of its name", arguments: formats)
    func aliasBesideProjectAlias(format: DiagramFormat) {
        let source = """
            class Base { var top = 0 }
            class Local { var local = 0 }
            struct Array { typealias Alias = Local }
            extension [Int] {
                typealias Alias = Base
                class Sub: Alias { func f() -> Int { top } }
            }
            """
        #expect(ends(from: "Array.Sub", source, format) == ["Base"])
    }

    @Test("a typealias in a project Array is its own beside a sugared extension's of its name", arguments: formats)
    func projectAliasBesideSugaredAlias(format: DiagramFormat) {
        let source = """
            class Base { var top = 0 }
            class Local { var local = 0 }
            extension [Int] { typealias Alias = Base }
            struct Array {
                typealias Alias = Local
                class Sub: Alias { func f() -> Int { local } }
            }
            """
        #expect(ends(from: "Array.Sub", source, format) == ["Local"])
    }

    /// The mirror: inside a project `struct Array`, `Base` is not one `extension [Int]` declares.
    @Test("a short name in a project Array is not a sugared extension's member", arguments: formats)
    func projectArraySkipsSugaredMember(format: DiagramFormat) {
        let source = """
            class Base { var top = 0 }
            extension [Int] { class Base { var sugar = 0 } }
            struct Array { class Sub: Base { func f() -> Int { top } } }
            """
        #expect(ends(from: "Array.Sub", source, format) == ["Base"])
    }

    /// Both are recorded as `Array.Base`, and the sugared one is declared first.
    @Test("a short name in a project Array is its own member, though a sugared extension's comes first")
    func projectArraySeesOwnMember() {
        let source = """
            extension [Int] { class Base { var sugar = 0 } }
            struct Array {
                class Base { var local = 0 }
                class Sub: Base { func f() -> Int { local } }
            }
            """
        #expect(endMembers(from: "Array.Sub", source) == [["~ local"]])
    }

    /// A bare `extension Array` beside a project `struct Array` extends the project's type.
    @Test("a short name in a bare extension of a project Array is its member, though a sugared one comes first")
    func bareExtensionOfProjectArraySeesOwnMember() {
        let source = """
            extension [Int] { class Base { var sugar = 0 } }
            struct Array { class Base { var local = 0 } }
            extension Array { class Sub: Base { func f() -> Int { local } } }
            """
        #expect(endMembers(from: "Array.Sub", source) == [["~ local"]])
    }

    @Test("a short name in a sugared extension is its own member beside a project Array's",
          arguments: [ExtensionVisualization.all, .merged])
    func shortNameFindsSugaredMember(mode: ExtensionVisualization) {
        let source = """
            struct Array { class Base { var local = 0 } }
            extension [Int] {
                class Base { var sugar = 0 }
                class Sub: Base { func f() -> Int { sugar } }
            }
            """
        #expect(endMembers(from: "Array.Sub", source, mode) == [["~ sugar"]])
    }

    // MARK: - A dotted name as written

    /// `Array.Base` written at the top level or in `extension [Int]` means the project's `Array`,
    /// whichever is declared first.
    @Test("a written Array.Base is the project Array's member", arguments: [
        "struct Array { class Base { var local = 0 } }\nextension [Int] { class Base { var sugar = 0 } }",
        "extension [Int] { class Base { var sugar = 0 } }\nstruct Array { class Base { var local = 0 } }"
    ])
    func writtenPathMeansProjectArray(declarations: String) {
        let sub = "class Sub: Array.Base { func f() -> Int { local } }"
        #expect(endMembers(from: "Sub", declarations + "\n" + sub) == [["~ local"]])
        #expect(endMembers(from: "Array.Sub", declarations + "\nextension [Int] { \(sub) }") == [["~ local"]])
    }

    /// The first component of `Array.Base` is looked up as a bare name: here `Outer`'s own
    /// `Array`, an alias of Swift's, whichever `Array.Base` is declared first.
    @Test("a written Array.Base reaches an enclosing type's typealias Array", arguments: [
        "extension [Int] { class Base { var sugar = 0 } }\nstruct Array { class Base { var local = 0 } }"
            + "\nenum Outer {}\nextension Outer { typealias Array = [Int] }",
        "struct Array { class Base { var local = 0 } }\nextension [Int] { class Base { var sugar = 0 } }"
            + "\nenum Outer {}\nextension Outer { typealias Array = [Int] }",
        "extension [Int] { class Base { var sugar = 0 } }\nstruct Array { class Base { var local = 0 } }"
            + "\nenum Outer { typealias Array = Swift.Array<Int> }"
    ], [ExtensionVisualization.all, .merged, .none])
    func writtenPathThroughEnclosingAlias(declarations: String, mode: ExtensionVisualization) {
        let source = declarations + "\nextension Outer { class Sub: Array.Base { func f() -> Int { sugar } } }"
        #expect(endMembers(from: "Outer.Sub", source, mode) == [["~ sugar"]])
    }

    @Test("a bare extension of Array.Base merges into the project Array's member, whichever is declared first")
    func bareExtensionOfPathMeansProjectArray() throws {
        let source = """
            extension [Int] { class Base { var sugar = 0 } }
            struct Array { class Base { var local = 0 } }
            extension Array.Base { var viaBare: Int { local } }
            """
        let graph = script(source, .svg, .merged).layoutGraph
        let projectBase = try #require(nested(in: "Array", graph))
        let members = graph?.nodes.first { $0.id == projectBase }?.compartments.flatMap(\.items) ?? []
        #expect(members.contains { $0.contains("viaBare") })
    }

    // MARK: - Alias chains

    /// Each alias's target is looked up from inside the extension, where `Target` is its own
    /// member. The lookup used to cut the last of eight steps short and end on the top-level one.
    @Test("an eight-alias chain in an extension still ends on the extension's member",
          arguments: formats, ["enum NS {}\nextension NS", "extension [Int]"])
    func longAliasChainInExtension(format: DiagramFormat, extensionHeader: String) {
        let chain = (2...8).map { "typealias A\($0) = A\($0 - 1)" }.joined(separator: "\n")
        let source = """
            class Target { var top = 0 }
            \(extensionHeader) {
                class Target { var inner = 0 }
                typealias A1 = Target
            \(chain)
                class Sub: A8 { func f() -> Int { inner } }
            }
            """
        let owner = extensionHeader == "extension [Int]" ? "Array" : "NS"
        if format == .svg {
            #expect(endMembers(from: "\(owner).Sub", source) == [["~ inner"]])
        } else {
            #expect(ends(from: "\(owner).Sub", source, format) == ["\(owner).Target"])
        }
    }

    // MARK: - Exclusion

    @Test("relationships.inheritance.exclude matches the supertype the name means")
    func excludeMatchesResolvedSupertype() {
        let source = """
            class Base { var top = 0 }
            struct Array { class Base { var local = 0 } }
            extension [Int] { class Sub: Base { func f() -> Int { top } } }
            """
        func excluding(_ patterns: [String]) -> RelationshipOptions {
            RelationshipOptions(inheritance: Relationship(label: "inherits", exclude: patterns))
        }
        #expect(ends(from: "Array.Sub", source, .plantuml, relationships: excluding(["Array.Base"])) == ["Base"])
        #expect(ends(from: "Array.Sub", source, .plantuml, relationships: excluding(["Base"])) == [])
    }

    // MARK: - Controls

    @Test("with no project Array, a sugared extension still sees a bare extension's member", arguments: formats)
    func noProjectArraySeesBareMember(format: DiagramFormat) {
        let source = """
            class Base { var top = 0 }
            extension Array { class Base { var bare = 0 } }
            extension [Int] { class Sub: Base { func f() -> Int { bare } } }
            """
        #expect(ends(from: "Array.Sub", source, format) == ["Array.Base"])
    }
}
