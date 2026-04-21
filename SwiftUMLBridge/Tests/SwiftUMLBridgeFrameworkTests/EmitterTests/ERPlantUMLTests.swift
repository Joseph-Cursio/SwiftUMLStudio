import Testing
@testable import SwiftUMLBridgeFramework

@Suite("ERScript — PlantUML")
struct ERPlantUMLTests {

    private func makeScript(model: ERModel) -> ERScript {
        var config = Configuration.default
        config.format = .plantuml
        return ERScript(model: model, configuration: config)
    }

    // MARK: - Header / footer

    @Test("wraps output in @startuml/@enduml")
    func wrapsInStartumlEnduml() {
        let script = makeScript(model: ERModel(entities: [EREntity(name: "Note")]))
        #expect(script.text.hasPrefix("@startuml"))
        #expect(script.text.hasSuffix("@enduml"))
    }

    // MARK: - Entity blocks

    @Test("entity block opens with entity keyword and quoted name")
    func entityBlockHeader() {
        let script = makeScript(model: ERModel(entities: [EREntity(name: "Author")]))
        #expect(script.text.contains("entity \"Author\" {"))
    }

    @Test("primary-key attribute is prefixed with asterisk")
    func primaryKeyPrefixed() {
        let model = ERModel(entities: [
            EREntity(name: "User", attributes: [
                ERAttribute(name: "id", type: "UUID", isPrimaryKey: true)
            ])
        ])
        let script = makeScript(model: model)
        #expect(script.text.contains("* id : UUID"))
    }

    @Test("non-primary-key attribute has no asterisk")
    func nonPrimaryNoAsterisk() {
        let model = ERModel(entities: [
            EREntity(name: "User", attributes: [
                ERAttribute(name: "name", type: "String")
            ])
        ])
        let script = makeScript(model: model)
        let nameLine = script.text.split(separator: "\n")
            .first(where: { $0.contains("name : String") })
        #expect(nameLine?.contains("*") == false)
    }

    @Test("separator line appears between PK and body when both exist")
    func separatorBetweenPKAndBody() {
        let model = ERModel(entities: [
            EREntity(name: "User", attributes: [
                ERAttribute(name: "id", type: "UUID", isPrimaryKey: true),
                ERAttribute(name: "name", type: "String")
            ])
        ])
        let script = makeScript(model: model)
        let lines = script.text.split(separator: "\n").map(String.init)
        guard let idIndex = lines.firstIndex(where: { $0.contains("* id") }),
              let nameIndex = lines.firstIndex(where: { $0.contains("name : String") }),
              let separatorIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "--" })
        else {
            Issue.record("expected id, name, and separator lines")
            return
        }
        #expect(idIndex < separatorIndex)
        #expect(separatorIndex < nameIndex)
    }

    @Test("entity with only PKs skips separator")
    func onlyPKsNoSeparator() {
        let model = ERModel(entities: [
            EREntity(name: "OnlyID", attributes: [
                ERAttribute(name: "id", type: "UUID", isPrimaryKey: true)
            ])
        ])
        let script = makeScript(model: model)
        #expect(script.text.contains("  --") == false)
    }

    @Test("entity with only non-PKs skips separator")
    func onlyBodyNoSeparator() {
        let model = ERModel(entities: [
            EREntity(name: "Misc", attributes: [
                ERAttribute(name: "name", type: "String")
            ])
        ])
        let script = makeScript(model: model)
        #expect(script.text.contains("  --") == false)
    }

    @Test("unique non-PK attribute gets <<UK>> stereotype")
    func uniqueNonPKStereotype() {
        let model = ERModel(entities: [
            EREntity(name: "User", attributes: [
                ERAttribute(name: "handle", type: "String", isUnique: true)
            ])
        ])
        let script = makeScript(model: model)
        #expect(script.text.contains("handle : String <<UK>>"))
    }

    @Test("transient attribute gets <<transient>> stereotype")
    func transientStereotype() {
        let model = ERModel(entities: [
            EREntity(name: "Cached", attributes: [
                ERAttribute(name: "preview", type: "String", isTransient: true)
            ])
        ])
        let script = makeScript(model: model)
        #expect(script.text.contains("preview : String <<transient>>"))
    }

    @Test("optional attribute renders trailing question mark on type")
    func optionalTypeMarker() {
        let model = ERModel(entities: [
            EREntity(name: "Profile", attributes: [
                ERAttribute(name: "bio", type: "String", isOptional: true)
            ])
        ])
        let script = makeScript(model: model)
        #expect(script.text.contains("bio : String?"))
    }

    // MARK: - Relationships

    @Test("emits crow's-foot relationship line with label")
    func relationshipLine() {
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

    @Test("relationship line appears after the entity blocks")
    func relationshipAfterEntities() {
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
        let lines = script.text.split(separator: "\n").map(String.init)
        guard let lastClose = lines.lastIndex(of: "}"),
              let edgeIndex = lines.firstIndex(where: { $0.contains("||--o{") })
        else {
            Issue.record("expected entity closing brace and edge line")
            return
        }
        #expect(lastClose < edgeIndex)
    }

    // MARK: - Empty

    @Test("empty model still wraps in @startuml/@enduml")
    func emptyModel() {
        let script = makeScript(model: ERModel())
        #expect(script.text == "@startuml\n@enduml")
    }
}
