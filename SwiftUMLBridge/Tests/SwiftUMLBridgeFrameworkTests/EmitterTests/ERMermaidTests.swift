import Testing
@testable import SwiftUMLBridgeFramework

@Suite("ERScript — Mermaid")
struct ERMermaidTests {

    private func makeScript(model: ERModel, format: DiagramFormat = .mermaid) -> ERScript {
        var config = Configuration.default
        config.format = format
        return ERScript(model: model, configuration: config)
    }

    // MARK: - Header

    @Test("starts with erDiagram header")
    func startsWithHeader() {
        let model = ERModel(entities: [EREntity(name: "Note")])
        let script = makeScript(model: model)
        #expect(script.text.hasPrefix("erDiagram"))
    }

    // MARK: - Entity blocks

    @Test("emits an entity block with attributes")
    func emitsEntityBlock() {
        let model = ERModel(entities: [
            EREntity(name: "Author", attributes: [
                ERAttribute(name: "identifier", type: "UUID", isPrimaryKey: true, isUnique: true),
                ERAttribute(name: "name", type: "String")
            ])
        ])
        let script = makeScript(model: model)
        #expect(script.text.contains("Author {"))
        #expect(script.text.contains("UUID identifier PK"))
        #expect(script.text.contains("String name"))
        #expect(script.text.contains("}"))
    }

    @Test("marks unique (non-PK) attribute with UK")
    func marksUniqueAsUK() {
        let model = ERModel(entities: [
            EREntity(name: "User", attributes: [
                ERAttribute(name: "id", type: "UUID", isPrimaryKey: true),
                ERAttribute(name: "handle", type: "String", isUnique: true)
            ])
        ])
        let script = makeScript(model: model)
        #expect(script.text.contains("String handle UK"))
        #expect(script.text.contains("UUID id PK"))
    }

    @Test("marks transient attribute with quoted transient comment")
    func marksTransient() {
        let model = ERModel(entities: [
            EREntity(name: "Cached", attributes: [
                ERAttribute(name: "preview", type: "String", isTransient: true)
            ])
        ])
        let script = makeScript(model: model)
        #expect(script.text.contains("String preview \"transient\""))
    }

    @Test("sanitizes bracketed type tokens")
    func sanitizesBracketType() {
        let model = ERModel(entities: [
            EREntity(name: "Thing", attributes: [
                ERAttribute(name: "tags", type: "[String]")
            ])
        ])
        let script = makeScript(model: model)
        // "[String]" has two non-alphanumerics; each becomes "_".
        #expect(script.text.contains("_String_ tags"))
    }

    // MARK: - Relationship symbols

    @Test("one-to-many relationship uses ||--o{")
    func oneToManyEdge() {
        let model = ERModel(
            entities: [EREntity(name: "Author"), EREntity(name: "Book")],
            relationships: [
                ERRelationship(
                    from: "Author", toEntity: "Book",
                    fromCardinality: .exactlyOne, toCardinality: .zeroOrMany,
                    label: "books"
                )
            ]
        )
        let script = makeScript(model: model)
        #expect(script.text.contains("Author ||--o{ Book : books"))
    }

    @Test("optional to-one relationship uses }o--o|")
    func optionalToOneEdge() {
        let model = ERModel(
            entities: [EREntity(name: "Book"), EREntity(name: "Author")],
            relationships: [
                ERRelationship(
                    from: "Book", toEntity: "Author",
                    fromCardinality: .zeroOrMany, toCardinality: .zeroOrOne,
                    label: "author"
                )
            ]
        )
        let script = makeScript(model: model)
        #expect(script.text.contains("Book }o--o| Author : author"))
    }

    @Test("many-to-many relationship uses }o--o{")
    func manyToManyEdge() {
        let model = ERModel(
            entities: [EREntity(name: "Book"), EREntity(name: "Tag")],
            relationships: [
                ERRelationship(
                    from: "Book", toEntity: "Tag",
                    fromCardinality: .zeroOrMany, toCardinality: .zeroOrMany,
                    label: "tags"
                )
            ]
        )
        let script = makeScript(model: model)
        #expect(script.text.contains("Book }o--o{ Tag : tags"))
    }

    @Test("one-to-one mandatory relationship uses ||--||")
    func oneToOneMandatory() {
        let model = ERModel(
            entities: [EREntity(name: "User"), EREntity(name: "Profile")],
            relationships: [
                ERRelationship(
                    from: "User", toEntity: "Profile",
                    fromCardinality: .exactlyOne, toCardinality: .exactlyOne,
                    label: "profile"
                )
            ]
        )
        let script = makeScript(model: model)
        #expect(script.text.contains("User ||--|| Profile : profile"))
    }

    @Test("one-or-many right end uses |{")
    func oneOrManyRight() {
        let model = ERModel(
            entities: [EREntity(name: "A"), EREntity(name: "B")],
            relationships: [
                ERRelationship(
                    from: "A", toEntity: "B",
                    fromCardinality: .exactlyOne, toCardinality: .oneOrMany,
                    label: "items"
                )
            ]
        )
        let script = makeScript(model: model)
        #expect(script.text.contains("A ||--|{ B : items"))
    }

    // MARK: - Empty / degenerate

    @Test("empty model produces just the header")
    func emptyModel() {
        let script = makeScript(model: ERModel())
        #expect(script.text == "erDiagram")
    }

    @Test("relationship without a label falls back to 'relates'")
    func unlabeledRelationship() {
        let model = ERModel(
            entities: [EREntity(name: "A"), EREntity(name: "B")],
            relationships: [
                ERRelationship(
                    from: "A", toEntity: "B",
                    fromCardinality: .exactlyOne, toCardinality: .exactlyOne,
                    label: ""
                )
            ]
        )
        let script = makeScript(model: model)
        #expect(script.text.contains("A ||--|| B : relates"))
    }

    // MARK: - Format piggybacking

    @Test("nomnoml format reuses the Mermaid emitter")
    func nomnomlFormatFallsBackToMermaid() {
        let model = ERModel(
            entities: [EREntity(name: "Note", attributes: [
                ERAttribute(name: "title", type: "String")
            ])]
        )
        let script = makeScript(model: model, format: .nomnoml)
        #expect(script.format == .nomnoml)
        #expect(script.text.hasPrefix("erDiagram"))
    }

    @Test("svg format reports mermaid format for web-rendered fallback")
    func svgFormatReportsMermaid() {
        let model = ERModel(entities: [EREntity(name: "Note")])
        let script = makeScript(model: model, format: .svg)
        #expect(script.format == .mermaid)
        #expect(script.text.hasPrefix("erDiagram"))
    }
}
