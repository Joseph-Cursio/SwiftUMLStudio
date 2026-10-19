import Testing
@testable import SwiftUMLBridgeFramework

/// `SyntaxStructure.clonedForest(of:)` gives class-diagram preparation a private copy to edit (#73).
@Suite("SyntaxStructure — cloned forest")
struct SyntaxStructureCloneTests {

    /// Every stored property, in declaration order. A new one fails `storedPropertiesArePinned`:
    /// decide whether `init(copying:)` must copy it, then add it here and to `populated(parent:)`.
    static let storedProperties = [
        "accessibility", "attribute", "attributes", "elements", "inheritedTypes", "kind", "name",
        "runtimename", "substructure", "typename", "memberSuffix", "parent", "sourceLocation", "module",
        "imports", "mergedInto", "carriedSupertypes", "standsInFor", "boundGenericArguments", "isSugared"
    ]

    /// A structure with every stored property set.
    private func populated(parent: SyntaxStructure) -> SyntaxStructure {
        let item = SyntaxStructure(
            accessibility: .public,
            attribute: "Observable",
            attributes: [SyntaxStructure(attribute: "MainActor")],
            elements: [SyntaxStructure(name: "element")],
            inheritedTypes: [SyntaxStructure(name: "Equatable")],
            kind: .struct,
            name: "Inner",
            runtimename: "Runtime",
            substructure: [SyntaxStructure(kind: .varInstance, name: "count", typename: "Int")],
            typename: "Inner.Type"
        )
        item.memberSuffix = "<&bolt>"
        item.parent = parent
        item.sourceLocation = SourceLocation(filePath: "A.swift", line: 3, column: 5)
        item.module = "Core"
        item.imports = ["Foundation"]
        item.mergedInto = parent
        item.standsInFor = parent
        let sendable = SyntaxStructure(kind: .protocol, name: "Sendable")
        item.carriedSupertypes = [SyntaxStructure.CarriedSupertype(supertype: sendable, scope: .init(of: item))]
        item.boundGenericArguments = "Int"
        item.isSugared = true
        return item
    }

    @Test("every stored property is pinned")
    func storedPropertiesArePinned() {
        let item = SyntaxStructure(kind: .struct, name: "Foo")
        #expect(Mirror(reflecting: item).children.compactMap(\.label) == Self.storedProperties)
        #expect(Mirror(reflecting: item).superclassMirror?.children.isEmpty ?? true)
    }

    @Test("a clone carries every stored property")
    func cloneCarriesEveryStoredProperty() throws {
        let outer = SyntaxStructure(kind: .struct, name: "Outer")
        let inner = populated(parent: outer)
        outer.substructure = [inner]
        let clonedOuter = try #require(SyntaxStructure.clonedForest(of: [outer]).first)
        let clone = try #require(clonedOuter.substructure?.first)
        let isCopy = clone !== inner
        #expect(isCopy)

        let originals = Mirror(reflecting: inner).children
        let copies = Mirror(reflecting: clone).children
        for (original, copy) in zip(originals, copies) {
            let label = original.label ?? "?"
            if let structures = original.value as? [SyntaxStructure] {
                let copied = try #require(copy.value as? [SyntaxStructure], "\(label) was dropped")
                #expect(copied.map(\.name) == structures.map(\.name), "\(label)")
                // Preparation writes into substructure, so it is copied; the other lists are shared.
                let shared = zip(copied, structures).allSatisfy { $0 === $1 }
                #expect(shared == (label != "substructure"), "\(label)")
            } else if let parent = original.value as? SyntaxStructure {
                let repointed = parent === outer && (copy.value as? SyntaxStructure) === clonedOuter
                #expect(repointed, "\(label) not re-pointed to the parent's copy")
            } else {
                #expect("\(original.value)" != "nil", "populated(parent:) must set \(label)")
                #expect("\(copy.value)" == "\(original.value)", "\(label)")
            }
        }
    }

    @Test("a parent outside the forest is kept")
    func parentOutsideTheForestIsKept() throws {
        let stale = SyntaxStructure(kind: .struct, name: "Mid")
        let inner = SyntaxStructure(kind: .struct, name: "Inner")
        inner.parent = stale
        let clone = try #require(SyntaxStructure.clonedForest(of: [inner]).first)
        let keptStale = clone.parent === stale
        #expect(keptStale)
        #expect(clone.fullName == "Mid.Inner")
    }

    @Test("a structure reached twice is copied once")
    func structureReachedTwiceIsCopiedOnce() throws {
        let inner = SyntaxStructure(kind: .struct, name: "Inner")
        let outer = SyntaxStructure(kind: .struct, name: "Outer", substructure: [inner])
        let clones = SyntaxStructure.clonedForest(of: [outer, inner])
        #expect(clones.count == 2)
        let copiedOnce = clones[1] === clones[0].substructure?.first && clones[1] !== inner
        #expect(copiedOnce)
    }

    @Test("merging a clone leaves the original as it was")
    func cloningLeavesTheOriginal() throws {
        let member = SyntaxStructure(kind: .functionMethodInstance, name: "bar")
        let ext = SyntaxStructure(
            inheritedTypes: [SyntaxStructure(name: "P")], kind: .extension, name: "Foo", substructure: [member]
        )
        let base = SyntaxStructure(kind: .struct, name: "Foo")
        let merged = SyntaxStructure.clonedForest(of: [base, ext]).mergeExtensions()
        #expect(merged.first?.substructure?.map(\.name) == ["bar"])
        #expect(merged.first?.substructure?.first?.memberSuffix == "<&bolt>")
        #expect(merged.first?.carriedSupertypes.map(\.supertype.name) == ["P"])
        #expect(base.substructure == nil)
        #expect(base.carriedSupertypes.isEmpty)
        #expect(member.memberSuffix == nil)
    }
}
