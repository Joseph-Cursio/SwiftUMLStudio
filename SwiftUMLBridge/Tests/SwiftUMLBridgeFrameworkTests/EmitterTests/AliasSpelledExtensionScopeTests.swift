import Testing
@testable import SwiftUMLBridgeFramework

/// Where a name written inside an extension goes when the type it means also has an extension
/// written through a typealias (`AliasSpelledExtensionEndTests`). Inside an extension of a type
/// outside the diagram, a name may be a member of that type, which the lookup cannot see, so it
/// is trusted only as written. Inside an extension of a project type it is the project's, whether
/// or not the lookup recorded that type. Every source passes `swiftc -typecheck`.
@Suite("A name written inside an extension reaches an alias-spelled extension as Swift reads it")
struct AliasSpelledExtensionScopeTests {

    static let formats: [DiagramFormat] = [.plantuml, .mermaid, .nomnoml, .svg]

    // MARK: - Inside an extension of a type outside the diagram

    /// `CustomStringConvertible` written in `extension Date`, or in `extension [Int]`, may be a
    /// member of Swift's type, so it reaches only an extension spelled as it is. Merged, that
    /// extension is gone into `extension Describable`'s box, and the edge ends there, as
    /// `Top`'s does; it was dropped from SVG, and written to an undeclared node in the others.
    static func stamped(in outside: String) -> String {
        """
        import Foundation
        typealias Describable = CustomStringConvertible
        extension Describable { func viaAlias() {} }
        extension CustomStringConvertible { func direct() {} }
        extension \(outside) { struct Stamp: CustomStringConvertible { var description: String { "" } } }
        struct Top: CustomStringConvertible { var description: String { "" } }
        """
    }

    @Test("an edge written in an outside type's extension ends on the box its spelling merged into",
          arguments: formats, [("Date", "Date.Stamp"), ("[Int]", "Array.Stamp")])
    func outsideTypeMemberEndsOnMergedBox(format: DiagramFormat, outside: (written: String, stamp: String)) {
        let source = Self.stamped(in: outside.written)
        let direct = format == .svg ? "~ direct()" : "CustomStringConvertible"
        #expect(supertypeEdgeEnds(from: outside.stamp, source, format, .all) == [direct])
        let merged = format == .svg ? "~ viaAlias()~ direct()" : "Describable"
        #expect(supertypeEdgeEnds(from: outside.stamp, source, format, .merged) == [merged])
        #expect(supertypeEdgeEnds(from: "Top", source, format, .merged) == [merged])
    }

    /// `Describable`, written in `extension Date`, is the project's typealias, as the lookup
    /// takes it everywhere else, though a name there may be one of `Date`'s members: only a name
    /// nothing the project declares takes is unsure. So `Date.Stamp`'s edge ends on the box
    /// `extension Describable` merged into, as `Top`'s does, and `extension Date.Desc` after
    /// `typealias Desc = Describable` in `extension Date` shares that type's box.
    @Test("a project typealias written in an outside type's extension is sure", arguments: formats)
    func projectAliasInOutsideTypeExtension(format: DiagramFormat) {
        let source = """
            import Foundation
            typealias Describable = CustomStringConvertible
            extension CustomStringConvertible { func direct() {} }
            extension Describable { func viaAlias() {} }
            extension Date { struct Stamp: Describable { var description: String { "" } } }
            struct Top: Describable { var description: String { "" } }
            """
        let merged = format == .svg ? "~ direct()~ viaAlias()" : "CustomStringConvertible"
        #expect(supertypeEdgeEnds(from: "Date.Stamp", source, format, .merged) == [merged])
        #expect(supertypeEdgeEnds(from: "Top", source, format, .merged) == [merged])
        let throughMember = """
            import Foundation
            typealias Describable = CustomStringConvertible
            extension Date { typealias Desc = Describable }
            extension Date.Desc { func viaDateAlias() {} }
            extension CustomStringConvertible { func direct() {} }
            struct T: CustomStringConvertible { var description: String { "" } }
            """
        let box = format == .svg ? "~ viaDateAlias()~ direct()" : "Date.Desc"
        #expect(supertypeEdgeEnds(from: "T", throughMember, format, .merged) == [box])
    }

    // MARK: - Inside an extension spelled through a typealias of an outside type

    /// `Day` and `Box.Stamp` are Foundation's `Date`, so `Style` inside an extension of either is
    /// `Date.FormatStyle`, as inside `extension Date`. Their first names being the project's
    /// typealiases made the extension count as a project type's, so `Shout`'s conformance to
    /// Foundation's protocol ended on `extension Day.Style`, and `--merge-extensions` folded
    /// `extension FormatStyle` into that box.
    static func styled(declaring declaration: String, extending extended: String, direct: Bool) -> String {
        """
        import Foundation
        \(declaration)
        extension \(extended) { typealias Style = FormatStyle }
        extension \(extended).Style { func viaMember() {} }
        \(direct ? "extension FormatStyle { func direct() {} }" : "")
        struct Shout: FormatStyle { func format(_ value: String) -> String { value.uppercased() } }
        """
    }

    /// `Box.Inner.Stamp` too, with nested types hidden, when the lookup records no `Box.Inner`.
    static let outsideAliases = [
        ("typealias Day = Date", "Day"), ("struct Box { typealias Stamp = Date }", "Box.Stamp"),
        ("struct Box { struct Inner { typealias Stamp = Date } }", "Box.Inner.Stamp")
    ]

    @Test("an alias written in an extension spelled through an outside type's typealias is no fallback",
          arguments: formats, [ExtensionVisualization.all, .merged])
    func aliasInExtensionThroughOutsideAlias(format: DiagramFormat, mode: ExtensionVisualization) {
        for (declaration, extended) in Self.outsideAliases {
            for nested in [true, false] {
                let alone = Self.styled(declaring: declaration, extending: extended, direct: false)
                #expect(supertypeEdgeEnds(from: "Shout", alone, format, mode, nestedTypes: nested)
                        == (format == .svg ? [] : ["FormatStyle"]), "\(extended) \(nested)")
                let beside = Self.styled(declaring: declaration, extending: extended, direct: true)
                let direct = format == .svg ? "~ direct()" : "FormatStyle"
                #expect(supertypeEdgeEnds(from: "Shout", beside, format, mode, nestedTypes: nested) == [direct],
                        "\(extended) \(nested)")
            }
        }
    }

    // MARK: - Inside an extension of a project type

    /// `Desc`, declared in `extension Outer.Inner`, is the project's, so `extension
    /// Outer.Inner.Desc` and `extension CustomStringConvertible` share a box, and `T`'s edge ends
    /// on it. With nested types hidden the lookup records no `Outer.Inner`, and `Desc` was taken
    /// for a member of a type outside the diagram, which kept the two boxes apart.
    static let nestedAlias = """
        struct Outer { struct Inner {} }
        extension Outer.Inner { typealias Desc = CustomStringConvertible }
        extension Outer.Inner.Desc { func viaAlias() {} }
        extension CustomStringConvertible { func direct() {} }
        struct T: CustomStringConvertible { var description: String { "" } }
        """

    @Test("an alias declared in an extension of a hidden nested project type merges with its type's extension",
          arguments: formats, [true, false])
    func aliasInNestedProjectTypeExtension(format: DiagramFormat, showNestedTypes: Bool) {
        let merged = format == .svg ? "~ viaAlias()~ direct()" : "Outer.Inner.Desc"
        #expect(
            supertypeEdgeEnds(from: "T", Self.nestedAlias, format, .merged, nestedTypes: showNestedTypes) == [merged]
        )
    }

    /// The same through `typealias Crate = Outer`: the lookup never resolves `Crate.Inner`, but
    /// `Crate` is the project's.
    @Test("an alias declared in an extension written through a project typealias merges with its type's extension",
          arguments: formats)
    func aliasInExtensionThroughProjectAlias(format: DiagramFormat) {
        let source = """
            struct Outer { struct Inner {} }
            typealias Crate = Outer
            extension Crate.Inner { typealias Desc = CustomStringConvertible }
            extension Crate.Inner.Desc { func viaAlias() {} }
            extension CustomStringConvertible { func direct() {} }
            struct T: CustomStringConvertible { var description: String { "" } }
            """
        let merged = format == .svg ? "~ viaAlias()~ direct()" : "Crate.Inner.Desc"
        #expect(supertypeEdgeEnds(from: "T", source, format, .merged) == [merged])
        // Through an alias of the nested type itself, which the lookup never records while
        // nested types are hidden: only `Crate`'s target's first name, `Outer`, is known.
        let ofNested = """
            struct Outer { struct Inner {} }
            typealias Crate = Outer.Inner
            extension Crate { typealias Desc = CustomStringConvertible }
            extension Crate.Desc { func viaAlias() {} }
            extension CustomStringConvertible { func direct() {} }
            struct T: CustomStringConvertible { var description: String { "" } }
            """
        let box = format == .svg ? "~ viaAlias()~ direct()" : "Crate.Desc"
        #expect(supertypeEdgeEnds(from: "T", ofNested, format, .merged, nestedTypes: false) == [box])
    }

    /// `Outer.Alias` is the project's `Outer.Inner`, which the lookup reads `Inner`, written
    /// inside `Outer`, as. The alias was looked up by its bare target, which found nothing, so
    /// `Desc` was taken for a member of a type outside the diagram: `T` reached no box, and
    /// `--merge-extensions` kept `extension CustomStringConvertible` apart. Declared in
    /// `extension Outer`, the alias is read the same way. With nested types hidden, the lookup
    /// records no `Outer.Inner`, so the target is found among the unlisted members of the type
    /// the alias is declared in.
    static func siblingAlias(declaring declaration: String, direct: Bool) -> String {
        """
        \(declaration)
        extension Outer.Alias { typealias Desc = CustomStringConvertible }
        extension Outer.Alias.Desc { func viaMember() {} }
        \(direct ? "extension CustomStringConvertible { func direct() {} }" : "")
        struct T: CustomStringConvertible { var description: String { "" } }
        """
    }

    static let siblingAliasDeclarations = [
        "struct Outer { struct Inner {}; typealias Alias = Inner }",
        "struct Outer { struct Inner {} }\nextension Outer { typealias Alias = Inner }"
    ]

    private func classLines(
        _ source: String, _ mode: ExtensionVisualization, showNestedTypes: Bool = true
    ) -> [Substring] {
        classDiagram(source, .plantuml, mode, nestedTypes: showNestedTypes).text.split(separator: "\n")
            .filter { $0.hasPrefix("class ") }
    }

    @Test("an alias declared in an extension written through an alias of a sibling nested type is the project's",
          arguments: formats, [true, false])
    func aliasInExtensionThroughSiblingAlias(format: DiagramFormat, showNestedTypes: Bool) {
        for declaration in Self.siblingAliasDeclarations {
            let alone = Self.siblingAlias(declaring: declaration, direct: false)
            let end = format == .svg ? "~ viaMember()" : "Outer.Alias.Desc"
            #expect(
                supertypeEdgeEnds(from: "T", alone, format, .all, nestedTypes: showNestedTypes)
                    == [end], "\(declaration)"
            )
            let both = Self.siblingAlias(declaring: declaration, direct: true)
            let boxes = classLines(both, .merged, showNestedTypes: showNestedTypes)
            #expect(boxes.contains { $0.contains("as Outer.Alias.Desc") }, "\(declaration)")
            #expect(!boxes.contains { $0.contains("as CustomStringConvertible") }, "\(declaration)")
        }
    }

    /// `Date.Box` is a struct the project declares in `extension Date`. Inside
    /// `extension Date.Box`, Swift looks a name up among `Box`'s members, never `Date`'s, so
    /// `Desc` is Swift's protocol. The first name being no project type's made the extension
    /// count as an outside type's, which kept `extension Date.Box.Desc` apart from
    /// `extension CustomStringConvertible` under `--merge-extensions`.
    @Test("an extension of a project type nested in an outside type's extension merges with its type's extension")
    func projectTypeNestedInOutsideExtensionMerges() {
        let source = """
            import Foundation
            extension Date { struct Box {} }
            extension Date.Box { typealias Desc = CustomStringConvertible }
            extension Date.Box.Desc { func viaMember() {} }
            extension CustomStringConvertible { func direct() {} }
            """
        let boxes = classLines(source, .merged)
        #expect(boxes.contains { $0.contains("as Date.Box.Desc") })
        #expect(!boxes.contains { $0.contains("as CustomStringConvertible") })
    }

    /// `MyModule.Outer` is the module's own `Outer`, written with its module.
    @Test("an alias declared in an extension of a module-qualified project type merges with its type's extension")
    func aliasInModuleQualifiedExtension() throws {
        let source = """
            struct Outer {}
            extension MyModule.Outer { typealias Desc = CustomStringConvertible }
            extension MyModule.Outer.Desc { func viaAlias() {} }
            extension CustomStringConvertible { func direct() {} }
            """
        let items = try #require(SyntaxStructure.create(from: source, module: "MyModule")?.substructure)
        let configuration = Configuration(elements: ElementOptions(showExtensions: .merged), format: .plantuml)
        let boxes = DiagramScript(items: items, configuration: configuration).text.split(separator: "\n")
            .filter { $0.hasPrefix("class ") }
        #expect(boxes.contains { $0.contains("as MyModule.Outer.Desc") })
        #expect(!boxes.contains { $0.contains("as CustomStringConvertible") })
    }

    // MARK: - Cost

    /// Eight levels of typealiases, each spelled through eight parts that are each a typealias of
    /// the level below. Only the longest part the lookup records decides whether the extension is
    /// the project's, so only its alias is followed: following every part's alias took eight to
    /// the eighth lookups for the one name written in the last extension.
    @Test("an extension spelled through many aliased parts is judged by its longest part alone")
    func manyAliasedPartsCostALookupAPart() throws {
        var lines = ["import Foundation", "struct Base {}"]
        var previous = "Base"
        for level in 1...8 {
            let names = (1...8).map { "L\(level)P\($0)" }
            lines.append("typealias \(names[0]) = \(previous)")
            for index in 1..<names.count {
                let extended = names[..<index].joined(separator: ".")
                lines.append("extension \(extended) { typealias \(names[index]) = \(previous) }")
            }
            previous = names.joined(separator: ".")
        }
        lines.append("extension \(previous) { typealias Desc = CustomStringConvertible }")
        lines.append("extension \(previous).Desc { func viaAlias() {} }")
        lines.append("extension CustomStringConvertible { func direct() {} }")
        // Parsed outside the clock, so a busy SourceKit does not count.
        let items = try #require(SyntaxStructure.create(from: lines.joined(separator: "\n"))?.substructure)
        let configuration = Configuration(elements: ElementOptions(showExtensions: .merged), format: .plantuml)
        let elapsed = ContinuousClock().measure { _ = DiagramScript(items: items, configuration: configuration) }
        #expect(elapsed < .seconds(2), "\(elapsed)")
    }
}
