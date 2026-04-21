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

    @Test(
        "cardinality pair renders the expected crow's-foot symbols",
        arguments: [
            (ERCardinality.exactlyOne, ERCardinality.zeroOrMany, "||--o{"),
            (ERCardinality.zeroOrMany, ERCardinality.zeroOrOne, "}o--o|"),
            (ERCardinality.zeroOrMany, ERCardinality.zeroOrMany, "}o--o{"),
            (ERCardinality.exactlyOne, ERCardinality.exactlyOne, "||--||"),
            (ERCardinality.exactlyOne, ERCardinality.oneOrMany, "||--|{")
        ]
    )
    func cardinalityPairs(fromCardinality: ERCardinality, toCardinality: ERCardinality, expected: String) {
        let model = ERModel(
            entities: [EREntity(name: "A"), EREntity(name: "B")],
            relationships: [
                ERRelationship(
                    from: "A", toEntity: "B",
                    fromCardinality: fromCardinality, toCardinality: toCardinality,
                    label: "edge"
                )
            ]
        )
        let script = makeScript(model: model)
        #expect(script.text.contains("A \(expected) B : edge"))
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
