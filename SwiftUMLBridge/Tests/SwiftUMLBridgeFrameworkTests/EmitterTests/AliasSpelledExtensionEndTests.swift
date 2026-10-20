import Testing
@testable import SwiftUMLBridgeFramework

/// An extension written through a typealias, `extension Describable` after
/// `typealias Describable = CustomStringConvertible`, extends the type the alias names, and
/// `mergeExtensions` already gives both spellings one box (#125). The edge ends looked a drawn
/// extension up only under the spelling the edge was written with, so `struct T:
/// CustomStringConvertible` did not reach `extension Describable`, a hidden protocol written
/// `P` did not reach its only stand-in, `extension Q`, and under `--merge-extensions` an edge
/// written with a merged-away spelling was dropped. Every source passes `swiftc -typecheck`; one
/// that extends `Host`, a type outside the diagram, with a file declaring `Host` beside it.
@Suite("An extension written through a typealias ends edges for every spelling of its type")
struct AliasSpelledExtensionEndTests {

    static let formats: [DiagramFormat] = [.plantuml, .mermaid, .nomnoml, .svg]

    private func script(
        _ source: String, _ format: DiagramFormat, _ mode: ExtensionVisualization = .all,
        exclude: [String]? = nil
    ) -> DiagramScript {
        let elements = ElementOptions(showExtensions: mode, exclude: exclude)
        let configuration = Configuration(elements: elements, format: format)
        return ClassDiagramGenerator().generateScript(for: source, with: configuration)
    }

    /// The id each supertype edge from `child` ends on, in SVG the members of that node, which
    /// tell the boxes apart.
    private func ends(
        from child: String, _ source: String, _ format: DiagramFormat, _ mode: ExtensionVisualization
    ) -> [String] {
        let drawn = script(source, format, mode)
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

    // MARK: - A type outside the diagram

    static let outside = """
        typealias Describable = CustomStringConvertible
        extension Describable { var shout: String { description.uppercased() } }
        struct S: Describable { var description: String { "s" } }
        struct T: CustomStringConvertible { var description: String { "t" } }
        """

    @Test("both spellings of an outside type end on its one extension, written through the alias",
          arguments: formats, [ExtensionVisualization.all, .merged])
    func outsideTypeBothSpellings(format: DiagramFormat, mode: ExtensionVisualization) {
        let box = format == .svg ? "~ shout: String" : "Describable"
        #expect(ends(from: "S", Self.outside, format, mode) == [box])
        #expect(ends(from: "T", Self.outside, format, mode) == [box])
    }

    /// Drawn apart, each spelling keeps its own extension, as before. Merged, the second is
    /// gone, and an edge written with its spelling ends on the box it merged into.
    static let bothSpelled = """
        typealias Describable = CustomStringConvertible
        extension CustomStringConvertible { var direct: Int { 0 } }
        extension Describable { var shout: String { description.uppercased() } }
        struct S: Describable { var description: String { "s" } }
        struct T: CustomStringConvertible { var description: String { "t" } }
        """

    @Test("with both spellings extended, an edge ends on its own spelling's box, or the box it merged into",
          arguments: formats)
    func bothSpellingsExtended(format: DiagramFormat) {
        let (direct, viaAlias) = format == .svg
            ? ("~ direct: Int", "~ shout: String") : ("CustomStringConvertible", "Describable")
        #expect(ends(from: "S", Self.bothSpelled, format, .all) == [viaAlias])
        #expect(ends(from: "T", Self.bothSpelled, format, .all) == [direct])
        let merged = format == .svg ? "~ direct: Int~ shout: String" : "CustomStringConvertible"
        #expect(ends(from: "S", Self.bothSpelled, format, .merged) == [merged])
        #expect(ends(from: "T", Self.bothSpelled, format, .merged) == [merged])
    }

    // MARK: - A hidden type

    /// The default access levels hide the `fileprivate` protocol; its only extension, written
    /// `Q`, stands in for it, whether a conformance spells it `P` or `Q`.
    @Test("a hidden type's stand-in, written through an alias, takes every spelling's edge",
          arguments: formats, [ExtensionVisualization.all, .merged])
    func hiddenTypeStandInThroughAlias(format: DiagramFormat, mode: ExtensionVisualization) {
        let source = """
            fileprivate protocol P { func base() }
            fileprivate typealias Q = P
            extension Q { func viaAlias() {} }
            struct U: P { func base() {} }
            struct V: Q { func base() {} }
            """
        let box = format == .svg ? "~ viaAlias()" : "Q"
        #expect(ends(from: "U", source, format, mode) == [box])
        #expect(ends(from: "V", source, format, mode) == [box])
    }

    // MARK: - A nested type

    /// The nesting edges `format` draws, as `parent -> child` in every format.
    private func nestingEdges(_ source: String, _ format: DiagramFormat, exclude: [String]) -> [String] {
        let drawn = script(source, format, exclude: exclude)
        switch format {
        case .svg:
            return drawn.layoutGraph?.edges.filter { $0.style == .composition }
                .map { "\($0.sourceId) -> \($0.targetId)" } ?? []
        case .nomnoml:
            return drawn.text.split(separator: "\n").compactMap { line -> String? in
                let parts = line.components(separatedBy: "] +- [")
                guard parts.count == 2 else { return nil }
                return "\(parts[0].dropFirst()) -> \(parts[1].dropLast())"
            }
        default:
            return drawn.text.split(separator: "\n").compactMap { line -> String? in
                let parts = line.components(separatedBy: " +-- ")
                return parts.count == 2 ? "\(parts[0]) -> \(parts[1])" : nil
            }
        }
    }

    static let nestingFormats: [DiagramFormat] = [.plantuml, .nomnoml, .svg]

    /// `elements.exclude` hides `extension Text`. The type nested in it hangs off the other drawn
    /// extension of `String`, as it would after a merge, not off an undeclared `Text`.
    @Test("a type nested in a hidden alias-spelled extension hangs off its type's other extension",
          arguments: nestingFormats)
    func nestedTypeOfHiddenAliasSpelledExtension(format: DiagramFormat) {
        let source = """
            typealias Text = String
            extension String { var direct: Int { 0 } }
            extension Text { struct Nested {} }
            """
        #expect(nestingEdges(source, format, exclude: ["Text"]) == ["String -> Text.Nested"])
    }

    /// `elements.exclude` hides `struct Box` and `extension Box`. A hidden type's only drawn
    /// extension, written through an alias, stands in for it, so the types nested in the type
    /// and in its hidden extension hang off that box.
    @Test("a hidden type's nested types hang off its stand-in written through an alias", arguments: nestingFormats)
    func nestedTypesHangOffAliasSpelledStandIn(format: DiagramFormat) {
        let inType = "struct Box { struct Inner {} }\ntypealias Crate = Box\nextension Crate { func viaAlias() {} }"
        #expect(nestingEdges(inType, format, exclude: ["Box"]) == ["Crate -> Box.Inner"])
        let inExtension = "struct Box {}\ntypealias Crate = Box\nextension Crate { func viaAlias() {} }\n"
            + "extension Box { struct Nested {} }"
        #expect(nestingEdges(inExtension, format, exclude: ["Box"]) == ["Crate -> Box.Nested"])
    }

    // MARK: - An alias written inside an extension of a type outside the diagram

    /// Inside `extension Host`, `Delegate` may be `Host.Delegate`, a member of a type the
    /// diagram cannot see, so `extension Host.HD` is no extension of the top-level `Delegate`
    /// that `T` conforms to. Swift reads it as `Host.Delegate` when Host declares one.
    static let hostAlias = """
        extension Host { typealias HD = Delegate }
        extension Host.HD { func callsHost() { hostOnly() } }
        struct T: Delegate { func topOnly() {} }
        """

    /// Foundation's case: `Style` is the struct `Date.FormatStyle`, not the protocol `FormatStyle`.
    static let dateStyle = """
        import Foundation
        extension Date { typealias Style = FormatStyle }
        extension Date.Style { var probeZone: TimeZone { timeZone } }
        struct Shouty: FormatStyle { func format(_ value: String) -> String { value.uppercased() } }
        """

    @Test("an alias written in an outside type's extension is no other outside type's fallback",
          arguments: formats, [ExtensionVisualization.all, .merged])
    func aliasInOutsideTypeExtensionIsNoFallback(format: DiagramFormat, mode: ExtensionVisualization) {
        #expect(ends(from: "T", Self.hostAlias, format, mode) == (format == .svg ? [] : ["Delegate"]))
        #expect(ends(from: "Shouty", Self.dateStyle, format, mode) == (format == .svg ? [] : ["FormatStyle"]))
    }

    @Test("--merge-extensions keeps an alias-spelled extension apart when the alias may name a member")
    func aliasInOutsideTypeExtensionKeepsItsBox() {
        let source = """
            extension Host { typealias HD = Delegate }
            extension Host.HD { func callsHost() { hostOnly() } }
            extension Delegate { func callsTop() { topOnly() } }
            """
        let boxes = script(source, .plantuml, .merged).text.split(separator: "\n").filter { $0.hasPrefix("class ") }
        #expect(boxes.contains { $0.contains("as Host.HD") })
        #expect(boxes.contains { $0.contains("as Delegate") })
    }

    /// As for an edge, the hidden extension's nested type keeps its own name rather than hang off
    /// `extension Item`, which may extend another type.
    @Test("a type nested in an alias-spelled extension that may name a member hangs off no other type's box",
          arguments: nestingFormats)
    func nestedTypeOfUnsureAliasSpelledExtension(format: DiagramFormat) {
        let source = """
            extension Host { typealias HI = Item }
            extension Host.HI { struct Nested {}
                func callsHost() { hostOnly() } }
            extension Item { func callsTop() { topOnly() } }
            """
        let edges = nestingEdges(source, format, exclude: ["HI"])
        #expect(!edges.contains { $0.hasPrefix("Item ") })
    }

    // MARK: - A typealias an alias-spelled extension declares

    /// `extension Crate` merges into `struct Outer`, which takes its members, but its
    /// `typealias Desc` is still `Crate.Desc`, so `extension Crate.Desc` extends
    /// `CustomStringConvertible` merged as it does drawn apart: an edge written
    /// `CustomStringConvertible` ends on it, and on the box `extension CustomStringConvertible`
    /// merges into beside it.
    static let memberOfAliasSpelled = """
        struct Outer {}
        typealias Crate = Outer
        extension Crate { typealias Desc = CustomStringConvertible }
        extension Crate.Desc { func viaAlias() {} }
        struct T: CustomStringConvertible { var description: String { "" } }
        """

    @Test("a typealias declared in an alias-spelled extension ends edges merged as drawn apart",
          arguments: formats, [ExtensionVisualization.all, .merged])
    func memberAliasOfAliasSpelledExtension(format: DiagramFormat, mode: ExtensionVisualization) {
        let box = format == .svg ? "~ viaAlias()" : "Crate.Desc"
        #expect(ends(from: "T", Self.memberOfAliasSpelled, format, mode) == [box])
        let bothSpelled = Self.memberOfAliasSpelled + "\nextension CustomStringConvertible { func direct() {} }"
        let merged = format == .svg ? "~ viaAlias()~ direct()" : "Crate.Desc"
        #expect(ends(from: "T", bothSpelled, format, .merged) == [merged])
    }

    @Test("so is one declared in an extension of a nested type spelled through an alias", arguments: formats)
    func memberAliasOfAliasSpelledNestedExtension(format: DiagramFormat) {
        let source = """
            struct Outer { struct Inner {} }
            typealias Alias = Outer.Inner
            extension Alias { typealias Desc = CustomStringConvertible }
            extension Alias.Desc { func viaAlias() {} }
            struct T: CustomStringConvertible { var description: String { "" } }
            """
        let box = format == .svg ? "~ viaAlias()" : "Alias.Desc"
        #expect(ends(from: "T", source, format, .merged) == [box])
    }

    // MARK: - Controls

    @Test("an outside type's edge never ends on another outside type's extension", arguments: formats)
    func otherOutsideTypeIsNotConflated(format: DiagramFormat) {
        let source = """
            typealias Same = Equatable
            extension Same { var viaAlias: Int { 0 } }
            struct S: Hashable { var value = 0 }
            """
        #expect(ends(from: "S", source, format, .all) == (format == .svg ? [] : ["Hashable"]))
    }
}
