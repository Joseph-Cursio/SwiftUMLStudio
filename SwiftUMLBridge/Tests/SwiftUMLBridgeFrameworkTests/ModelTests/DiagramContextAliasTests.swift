import Testing
@testable import SwiftUMLBridgeFramework

/// `uniqName` must hand out an alias no other element of the diagram uses (#54).
@Suite("DiagramContext — distinct aliases")
struct DiagramContextAliasTests {

    @Test("one context never issues the same alias twice")
    func uniqNameIssuesDistinctAliases() {
        let ctx = DiagramContext()
        let aliases = [
            ctx.uniqName(item: SyntaxStructure(kind: .struct, name: "Foo0"), relationship: "inherits"),
            ctx.uniqName(item: SyntaxStructure(kind: .struct, name: "Foo"), relationship: "inherits"),
            ctx.uniqName(item: SyntaxStructure(kind: .extension, name: "Foo"), relationship: "ext")
        ]
        #expect(aliases == ["Foo0", "Foo", "Foo1"])
        #expect(ctx.extnConnections == ["Foo <.. Foo1 : ext"])
    }

    @Test("a reserved name is skipped by a suffix issued before its own declaration")
    func reservedNameIsNotIssuedAsSuffix() {
        let ctx = DiagramContext()
        let items = [
            SyntaxStructure(kind: .struct, name: "Foo"),
            SyntaxStructure(kind: .extension, name: "Foo"),
            SyntaxStructure(kind: .extension, name: "Foo0")
        ]
        ctx.reserveIdentifiers(drawing: items)
        let aliases = items.map { ctx.uniqName(item: $0, relationship: $0.kind == .extension ? "ext" : "inherits") }
        #expect(aliases == ["Foo", "Foo1", "Foo0"])
    }

    @Test("a reserved name still counts as a first declaration")
    func reservedNameKeepsFirstDeclaration() {
        let ctx = DiagramContext()
        let item = SyntaxStructure(kind: .struct, name: "Foo0")
        ctx.reserveIdentifiers(drawing: [item])
        #expect(ctx.uniqName(item: item, relationship: "inherits") == "Foo0")
        #expect(ctx.uniqElementNames == ["Foo0"])
        #expect(ctx.uniqElementAndTypes["Foo0LinkType"] == "<|--")
    }

    @Test("a suffixed alias is never reissued under another base name")
    func suffixedAliasIsRecorded() {
        let ctx = DiagramContext()
        var aliases = [
            ctx.uniqName(item: SyntaxStructure(kind: .struct, name: "X1"), relationship: "inherits"),
            ctx.uniqName(item: SyntaxStructure(kind: .struct, name: "X"), relationship: "inherits"),
            ctx.uniqName(item: SyntaxStructure(kind: .extension, name: "X1"), relationship: "ext")
        ]
        // The counter reaches 10 on the last repeat of X, which offers the X10 already issued.
        for _ in 0..<9 {
            aliases.append(ctx.uniqName(item: SyntaxStructure(kind: .extension, name: "X"), relationship: "ext"))
        }
        #expect(Set(aliases).count == aliases.count, "\(aliases)")
        #expect(aliases[2] == "X10")
        #expect(aliases.last == "X11")
    }

    @Test("an edge's undrawn supertype is reserved, with an excluded edge's target left free")
    func linkTargetsAreReserved() {
        let config = Configuration(relationships: RelationshipOptions(inheritance: Relationship(exclude: ["Hidden0"])))
        let ctx = DiagramContext(configuration: config)
        let child = SyntaxStructure(
            inheritedTypes: [SyntaxStructure(name: "Base0"), SyntaxStructure(name: "Hidden0")],
            kind: .class,
            name: "C"
        )
        ctx.reserveIdentifiers(drawing: [child])
        #expect(ctx.takenIdentifiers == ["C", "Base0"])
    }

    /// `realize.exclude` is pooled with `inheritance.exclude` at the same gate, so an edge it
    /// hides leaves its target free too (#113).
    @Test("a realize-excluded edge's target is left free as well")
    func realizeExcludedTargetIsNotReserved() {
        let config = Configuration(relationships: RelationshipOptions(realize: Relationship(exclude: ["Hidden0"])))
        let ctx = DiagramContext(configuration: config)
        let child = SyntaxStructure(
            inheritedTypes: [SyntaxStructure(name: "Base0"), SyntaxStructure(name: "Hidden0")],
            kind: .struct,
            name: "C"
        )
        ctx.reserveIdentifiers(drawing: [child])
        #expect(ctx.takenIdentifiers == ["C", "Base0"])
    }

    @Test("each part of a composition is reserved")
    func compositionPartsAreReserved() {
        let ctx = DiagramContext()
        let child = SyntaxStructure(inheritedTypes: [SyntaxStructure(name: "P & Base0")], kind: .struct, name: "C")
        ctx.reserveIdentifiers(drawing: [child])
        #expect(ctx.takenIdentifiers == ["C", "P", "Base0"])
    }
}
