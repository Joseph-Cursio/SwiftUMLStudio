@testable import SwiftUMLBridgeFramework
import Testing

private typealias File = NearestDirectoryFixture.File

private func parsed(_ files: [File]) throws -> [SyntaxStructure] {
    try NearestDirectoryFixture.parsed(files)
}

private func edges(_ files: [File], _ elements: ElementOptions = ElementOptions()) throws -> [String] {
    try NearestDirectoryFixture.edges(files, elements)
}

private func lines(
    _ files: [File], _ format: DiagramFormat, _ elements: ElementOptions = ElementOptions()
) throws -> [String] {
    try NearestDirectoryFixture.lines(files, format, elements)
}

@Suite("Ranking by directory reaches every format")
struct NearestDirectoryFormatTests {

    private static let writers: [File] = [
        ("PkgA/Sources/A/Base.swift", "class Base {}"),
        ("PkgB/Sources/B/Base.swift", "protocol Base {}"),
        ("PkgA/Sources/A/SubA.swift", "class SubA: Base {}"),
        ("PkgB/Sources/B/SubB.swift", "class SubB: Base {}"),
        ("PkgB/Sources/B/SubC.swift", "class SubC: Base {}"),
    ]

    /// `typeWithSureKind` keeps its answers among writers it holds alike, so with no directory in
    /// them the second writer took the first one's `Base`, in the text formats alone. Protocols
    /// are drawn first, so PkgB's `Base` is the plain `Base`, and the label tells the two apart.
    @Test("writers in two trees each end on their own, in every format, whichever is asked first",
          arguments: [false, true])
    func formatsAgree(reversedWriters: Bool) throws {
        let files = Array(Self.writers[..<2])
            + (reversedWriters ? Array(Self.writers[2...].reversed()) : Array(Self.writers[2...]))
        #expect(Set(try edges(files)) == ["SubA -> Base_1", "SubB -> Base", "SubC -> Base"])
        for format in [DiagramFormat.plantuml, .mermaid] {
            let text = try lines(files, format)
            #expect(text.contains("Base0 <|-- SubA : inherits"), "\(text)")
            #expect(text.contains("Base <|.. SubB : conforms to"), "\(text)")
            #expect(text.contains("Base <|.. SubC : conforms to"), "\(text)")
        }
        let nomnoml = try lines(files, .nomnoml)
        #expect(nomnoml.contains("[SubA] -:> inherits [Base0]"), "\(nomnoml)")
        #expect(nomnoml.contains("[SubB] --:> conforms to [Base]"), "\(nomnoml)")
    }

    /// The same one depth down: each directory's alias means its own directory's `Base`.
    @Test("an alias's target is looked up from the alias's directory, in SVG and the text formats")
    func aliasTargetsStayHome() throws {
        let files: [File] = [
            ("PkgA/Base.swift", "class Base {}"),
            ("PkgB/Base.swift", "protocol Base {}"),
            ("PkgA/Alias.swift", "typealias Parent = Base"),
            ("PkgB/Alias.swift", "typealias Parent = Base"),
            ("PkgA/SubA.swift", "class SubA: Parent {}"),
            ("PkgB/SubB.swift", "class SubB: Parent {}"),
        ]
        #expect(Set(try edges(files)) == ["SubA -> Base_1", "SubB -> Base"])
        let text = try lines(files, .plantuml)
        #expect(text.contains("Base0 <|-- SubA : inherits"), "\(text)")
        #expect(text.contains("Base <|.. SubB : conforms to"), "\(text)")
    }

    /// What a supertype edge ends on, as SVG finds it and as the text formats do, through the
    /// shared memo, for each kind of name a directory can decide.
    @Test("the text formats' lookup and SVG's agree on every end, asked in either order", arguments: [false, true])
    func bothLookupsAgree(reversed: Bool) throws {
        let files: [File] = [
            ("/r/A/Base.swift", "class Base {}"),
            ("/r/B/Base.swift", "protocol Base {}"),
            ("/r/C/Base.swift", "typealias Base = Real"),
            ("/r/C/Real.swift", "class Real {}"),
            ("/r/A/Foo.swift", "struct Foo { class V {} }"),
            ("/r/B/Foo.swift", "struct Foo { typealias V = Base }"),
            ("/r/A/W1.swift", "class W1: Base {}\nclass W2: Foo.V {}"),
            ("/r/B/W3.swift", "class W3: Base {}\nclass W4: Foo.V {}"),
            ("/r/C/W5.swift", "class W5: Base {}\nclass W6: Foo.V {}"),
            ("/r/C/Sub/W7.swift", "class W7: Base {}\nclass W8: Foo.V {}"),
        ]
        let prepared = try parsed(files).preparedForClassDiagram(with: Configuration(format: .svg))
        var endIds = LayoutGraphBuilder.EdgeEndIds()
        for (index, item) in prepared.enumerated() {
            guard let kind = item.kind, ElementKind.processable.contains(kind),
                  let name = item.fullName ?? item.name else { continue }
            endIds.record(String(index), for: LayoutGraphBuilder.DiagramItem(
                item: item, kind: kind, name: name, isDrawn: true
            ))
        }
        endIds.recordAliases(in: prepared)
        let parents = prepared.flatMap { $0.linkParents() }
        #expect(parents.count == 8)
        for parent in reversed ? parents.reversed() : parents {
            let name = try #require(parent.supertype.name)
            let end = endIds.id(of: .named(name, from: parent.scope))
            #expect(endIds.supertype(named: name, from: parent.scope).id == end)
        }
    }
}
