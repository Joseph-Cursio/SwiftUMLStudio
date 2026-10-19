import Testing
@testable import SwiftUMLBridgeFramework

/// What a name written inside an extension means once `--merge-extensions` moves the extension's
/// members into its type, and inside an extension spelled through typealiases. Merging must not
/// change what a name means: a typealias an extension declares is read where that extension
/// declares it, which sees the members of the type it extends, under whatever spelling, but not
/// those of the types around that type. Every source passes `swiftc -typecheck`.
@Suite("A name written in an extension means the same merged or drawn apart")
struct MergedExtensionScopeTests {

    static let formats: [DiagramFormat] = [.plantuml, .mermaid, .nomnoml, .svg]

    private func script(
        _ source: String, _ format: DiagramFormat, _ mode: ExtensionVisualization, showNestedTypes: Bool = true
    ) -> DiagramScript {
        let elements = ElementOptions(showNestedTypes: showNestedTypes, showExtensions: mode)
        let configuration = Configuration(elements: elements, format: format)
        return ClassDiagramGenerator().generateScript(for: source, with: configuration)
    }

    /// The id each supertype edge from `child` ends on, in SVG the members of that node, which
    /// tell the boxes apart.
    private func ends(
        from child: String, _ source: String, _ format: DiagramFormat, _ mode: ExtensionVisualization,
        showNestedTypes: Bool = true
    ) -> [String] {
        let drawn = script(source, format, mode, showNestedTypes: showNestedTypes)
        switch format {
        case .svg:
            let graph = drawn.layoutGraph
            return graph?.edges.filter { $0.sourceId == child && $0.style != .composition }.map { edge in
                (graph?.nodes.first { $0.id == edge.targetId }?.compartments.flatMap(\.items) ?? []).joined()
            } ?? []
        case .nomnoml:
            return drawn.text.split(separator: "\n").compactMap { line -> String? in
                guard line.hasPrefix("[\(child)] -"), let open = line.lastIndex(of: "[") else { return nil }
                return String(line[line.index(after: open)...].dropLast())
            }
        default:
            return drawn.text.split(separator: "\n").compactMap { line -> String? in
                let words = line.split(separator: " ")
                guard words.count >= 3, ["<|--", "<|.."].contains(words[1]), words[2] == child else { return nil }
                return String(words[0])
            }
        }
    }

    private func boxes(_ source: String, showNestedTypes: Bool = true) -> [Substring] {
        script(source, .plantuml, .merged, showNestedTypes: showNestedTypes).text.split(separator: "\n")
            .filter { $0.hasPrefix("class ") }
    }

    // MARK: - An extension spelled through a typealias sees its type's members

    /// Inside `extension Crate`, `Inner` is `Outer.Inner`, a member of the type `Crate` aliases,
    /// not the top-level class. It was looked up as `Crate.Inner` only, and so took the class.
    static let crateMember = """
        struct Outer { protocol Inner { func inner() } }
        class Inner { func top() {} }
        typealias Crate = Outer
        extension Crate { struct Item: Inner { func inner() {} } }
        """

    @Test("a name written in an extension spelled through a typealias is a member of its type",
          arguments: formats, [ExtensionVisualization.all, .merged])
    func aliasSpelledExtensionSeesItsTypesMembers(format: DiagramFormat, mode: ExtensionVisualization) {
        let protocolEnd = format == .svg ? "~ inner()" : "Outer.Inner"
        #expect(ends(from: "Crate.Item", Self.crateMember, format, mode) == [protocolEnd])
    }

    /// Merged into `struct Outer`, `extension Crate`'s `typealias Desc = Inner` is recorded as
    /// both `Outer.Desc` and `Crate.Desc`. The two copies were read in different scopes, and the
    /// first one asked decided both: an edge written `Outer.Desc` after one written `Crate.Desc`
    /// ended on the top-level class, or on nothing without it.
    @Test("a typealias merged into its type means one type under each spelling, whichever is asked first",
          arguments: formats, [true, false])
    func mergedAliasMeansOneType(format: DiagramFormat, crateWriterFirst: Bool) {
        let writers = [
            "struct ViaCrate: Crate.Desc { func inner() {} }", "struct ViaOuter: Outer.Desc { func inner() {} }"
        ]
        let source = """
            struct Outer {}
            typealias Crate = Outer
            extension Outer { protocol Inner { func inner() } }
            class Inner { func top() {} }
            extension Crate { typealias Desc = Inner }
            \((crateWriterFirst ? writers : writers.reversed()).joined(separator: "\n"))
            """
        let protocolEnd = format == .svg ? "~ inner()" : "Outer.Inner"
        for mode in [ExtensionVisualization.all, .merged] {
            #expect(ends(from: "ViaOuter", source, format, mode) == [protocolEnd], "\(mode)")
            #expect(ends(from: "ViaCrate", source, format, mode) == [protocolEnd], "\(mode)")
        }
    }

    /// `extension Crate { typealias D = Date }` makes `Outer.D` `Date`, so `Style` in
    /// `extension Outer.D` is `Date.FormatStyle`. Drawn apart, only `Crate.D` was recorded, so
    /// `Outer.D` was taken as a member of the project's `Outer` and `Shout`'s conformance ended on
    /// `extension Outer.D.Style`; merged, that extension took `extension FormatStyle`'s members.
    @Test("a typealias an alias-spelled extension declares is known by its type's own name",
          arguments: formats, [ExtensionVisualization.all, .merged])
    func aliasSpelledExtensionsAliasUnderTypesName(format: DiagramFormat, mode: ExtensionVisualization) {
        let alone = """
            import Foundation
            struct Outer {}
            typealias Crate = Outer
            extension Crate { typealias D = Date }
            extension Outer.D { typealias Style = FormatStyle }
            extension Outer.D.Style { func viaMember() {} }
            struct Shout: FormatStyle { func format(_ value: String) -> String { value.uppercased() } }
            """
        #expect(ends(from: "Shout", alone, format, mode) == (format == .svg ? [] : ["FormatStyle"]))
        let both = alone + "\nextension FormatStyle { func direct() {} }"
        #expect(ends(from: "Shout", both, format, mode) == [format == .svg ? "~ direct()" : "FormatStyle"])
    }

    // MARK: - A merged typealias is read where its extension declares it

    /// Merged into the `Box` declared in `extension Date`, `extension Date.Box`'s typealias was
    /// read in `Box`'s scope, where `CustomStringConvertible` might be a member of `Date`, so `T`'s
    /// edge was dropped from SVG and written to an undeclared node in the others. Swift reads it in
    /// `extension Date.Box`, which sees `Box`'s members, never `Date`'s. Nested types hidden, the
    /// lookup records no `Date.Box`, but knows it is one of the project's.
    @Test("a typealias merged into a type nested in an outside type's extension ends edges as drawn apart",
          arguments: formats, [true, false])
    func mergedAliasOfNestedTypeEndsEdges(format: DiagramFormat, showNestedTypes: Bool) {
        let declarations = """
            import Foundation
            extension Date { struct Box {} }
            extension Date.Box { typealias Desc = CustomStringConvertible }
            extension Date.Box.Desc { func viaMember() {} }
            struct T: CustomStringConvertible { var description: String { "" } }
            """
        let alone = format == .svg ? "~ viaMember()" : "Date.Box.Desc"
        for mode in [ExtensionVisualization.all, .merged] {
            #expect(ends(from: "T", declarations, format, mode, showNestedTypes: showNestedTypes) == [alone], "\(mode)")
        }
        let both = declarations + "\nextension CustomStringConvertible { func direct() {} }"
        let merged = format == .svg ? "~ viaMember()~ direct()" : "Date.Box.Desc"
        #expect(ends(from: "T", both, format, .merged, showNestedTypes: showNestedTypes) == [merged])
    }

    /// Inside `extension Outer.Inner`, `Base` is the top-level protocol, never `Outer.Base`:
    /// `let base: any Base = S()` typechecks. Merged into `Inner`, whose body would see
    /// `Outer.Base`, the typealias is still read where it is written.
    @Test("a typealias merged into a nested type is read in its extension's scope", arguments: formats)
    func mergedAliasKeepsExtensionScope(format: DiagramFormat) {
        let source = """
            protocol Base { func top() }
            struct Outer { protocol Base { func nested() }; struct Inner {} }
            extension Outer.Inner { typealias Alias = Base }
            struct S: Outer.Inner.Alias { func top() {} }
            """
        let topLevel = format == .svg ? "~ top()" : "Base"
        for mode in [ExtensionVisualization.all, .merged] {
            #expect(ends(from: "S", source, format, mode) == [topLevel], "\(mode)")
        }
    }

    // MARK: - The parts after a typealias in an extension's name

    /// `Crate.D` is `Outer.D`, which is `Date`, so `Style` in `extension Crate.D` is
    /// `Date.FormatStyle`, not Foundation's protocol. Only `Crate` was followed, to the project's
    /// `Outer`, so `Fmt`'s conformance ended on `extension Crate.D.Style`.
    @Test("the parts after a typealias in an extension's name are members of what it stands for",
          arguments: formats, [ExtensionVisualization.all, .merged])
    func partsAfterAnAliasAreItsMembers(format: DiagramFormat, mode: ExtensionVisualization) {
        let source = """
            import Foundation
            struct Outer { typealias D = Date }
            typealias Crate = Outer
            extension Crate.D { typealias Style = FormatStyle }
            extension Crate.D.Style { func viaAlias() {} }
            extension FormatStyle { func direct() {} }
            struct Fmt: FormatStyle { func format(_ value: Int) -> String { "" } }
            """
        #expect(ends(from: "Fmt", source, format, mode) == [format == .svg ? "~ direct()" : "FormatStyle"])
    }

    /// `Day.Box` is the project's `Date.Box`, and `Crate.Alias` the project's `Outer.Inner`, so
    /// `Desc` in an extension of either is Swift's protocol, and its extension shares
    /// `extension CustomStringConvertible`'s box.
    @Test("an extension of a project type spelled through typealiases merges with its type's extension",
          arguments: [
            ("typealias Day = Date\nextension Date { struct Box {} }", "Day.Box"),
            ("struct Outer { struct Inner {} }\ntypealias Crate = Outer\nextension Crate { typealias Alias = Inner }",
             "Crate.Alias")
          ])
    func projectTypeSpelledThroughAliasesMerges(declarations: String, extended: String) {
        let source = """
            import Foundation
            \(declarations)
            extension \(extended) { typealias Desc = CustomStringConvertible }
            extension \(extended).Desc { func viaAlias() {} }
            extension CustomStringConvertible { func direct() {} }
            """
        #expect(boxes(source).contains { $0.contains("as \(extended).Desc") })
        #expect(!boxes(source).contains { $0.contains("as CustomStringConvertible") })
    }

    /// Inside `extension JSON`, after `typealias JSON = [String: Int]`, `Base` is the
    /// `Dictionary.Base` the project declares in `extension Dictionary`, not the top-level class,
    /// merged or drawn apart. Merged, `B` was read in `extension JSON`, whose type outside the
    /// diagram had no recorded name, and took the top-level class.
    @Test("a name in an alias-spelled extension of an outside type is that type's project member",
          arguments: formats, [ExtensionVisualization.merged])
    func aliasSpelledOutsideExtensionSeesItsTypesMembers(format: DiagramFormat, mode: ExtensionVisualization) {
        let source = """
            extension Dictionary { class Base { func nested() {} } }
            class Base { func top() {} }
            typealias JSON = [String: Int]
            extension JSON { typealias B = Base }
            class Sub: Dictionary<String, Int>.B {}
            """
        #expect(ends(from: "Sub", source, format, mode) == [format == .svg ? "~ nested()" : "Dictionary.Base"])
    }

    /// `X` in `extension Day`, after `typealias Day = Date`, is `Date.Y`, the protocol the
    /// project declares in `extension Date`, whichever spelling an edge writes.
    @Test("a typealias in an alias-spelled extension of an outside type means that type's member",
          arguments: formats, ["Date.X", "Day.X"])
    func aliasInAliasSpelledOutsideExtension(format: DiagramFormat, written: String) {
        let source = """
            import Foundation
            extension Date { protocol Y { func y() } }
            protocol Y { func top() }
            typealias Day = Date
            extension Day { typealias X = Y }
            struct T: \(written) { func y() {} }
            """
        #expect(ends(from: "T", source, format, .merged) == [format == .svg ? "~ y()" : "Date.Y"])
    }
}
