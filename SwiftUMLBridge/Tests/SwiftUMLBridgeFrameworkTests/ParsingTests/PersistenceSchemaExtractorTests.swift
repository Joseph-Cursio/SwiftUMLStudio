import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

@Suite("PersistenceSchemaExtractor — GRDB")
struct PersistenceSchemaExtractorGRDBTests {

    /// Locate fixtures under TestFixtures/SampleProject/Persistence/. Walks
    /// up five levels from #filePath to the repo root.
    private func fixturePath(_ name: String) -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        return testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TestFixtures/SampleProject/Persistence")
            .appendingPathComponent(name)
            .path
    }

    private func extractFromFixture(_ name: String) throws -> ERModel {
        let source = try String(contentsOfFile: fixturePath(name), encoding: .utf8)
        return PersistenceSchemaExtractor.extract(from: source)
    }

    // MARK: - Positive cases

    @Test("GRDBPlayer: detects three GRDB record types")
    func grdbPlayerEntities() throws {
        let model = try extractFromFixture("GRDBPlayer.swift")
        #expect(Set(model.entities.map(\.name)) == ["Player", "Team", "Score"])
    }

    @Test("GRDBPlayer: Player attributes are extracted from stored properties")
    func grdbPlayerAttributes() throws {
        let model = try extractFromFixture("GRDBPlayer.swift")
        let player = try #require(model.entities.first { $0.name == "Player" })
        #expect(Set(player.attributes.map(\.name)) == ["id", "name", "teamId"])
        let id = try #require(player.attributes.first { $0.name == "id" })
        #expect(id.isPrimaryKey == true)
        #expect(id.isOptional == true)
        let name = try #require(player.attributes.first { $0.name == "name" })
        #expect(name.type == "String")
        #expect(name.isOptional == false)
    }

    @Test("GRDBPlayer: belongsTo Team is many → one")
    func grdbBelongsToCardinality() throws {
        let model = try extractFromFixture("GRDBPlayer.swift")
        let edge = try #require(
            model.relationships.first { $0.from == "Player" && $0.toEntity == "Team" }
        )
        #expect(edge.fromCardinality == .zeroOrMany)
        #expect(edge.toCardinality == .exactlyOne)
        #expect(edge.label == "team")
    }

    @Test("GRDBPlayer: hasMany Score is one → many")
    func grdbHasManyCardinality() throws {
        let model = try extractFromFixture("GRDBPlayer.swift")
        let edge = try #require(
            model.relationships.first { $0.from == "Player" && $0.toEntity == "Score" }
        )
        #expect(edge.fromCardinality == .exactlyOne)
        #expect(edge.toCardinality == .zeroOrMany)
        #expect(edge.label == "scores")
    }

    @Test("GRDBPlayer: relationship-defining static lets are not also captured as columns")
    func grdbStaticAssociationsAreNotColumns() throws {
        let model = try extractFromFixture("GRDBPlayer.swift")
        let player = try #require(model.entities.first { $0.name == "Player" })
        #expect(player.attributes.contains(where: { $0.name == "team" }) == false)
        #expect(player.attributes.contains(where: { $0.name == "scores" }) == false)
    }

    @Test("GRDBPlayerNoAssociations: a record with no associations still emits its entity")
    func grdbStandaloneEntity() throws {
        let model = try extractFromFixture("GRDBPlayerNoAssociations.swift")
        let player = try #require(model.entities.first { $0.name == "StandalonePlayer" })
        #expect(Set(player.attributes.map(\.name)) == ["id", "nickname", "rank"])
        #expect(model.relationships.isEmpty)
    }

    // MARK: - Negative case

    @Test("NotPersistence: plain types yield zero entities")
    func notPersistenceProducesNothing() throws {
        let model = try extractFromFixture("NotPersistence.swift")
        #expect(model.entities.isEmpty)
        #expect(model.relationships.isEmpty)
    }

    // MARK: - Edge cases

    @Test("conformance via & composition is recognised")
    func compositionConformance() {
        let source = """
        struct Player: Codable & FetchableRecord & PersistableRecord {
            var id: Int64
        }
        """
        let model = PersistenceSchemaExtractor.extract(from: source)
        #expect(model.entities.first?.name == "Player")
    }

    @Test("hasOne is one → zeroOrOne")
    func hasOneCardinality() throws {
        let source = """
        struct Player: FetchableRecord {
            var id: Int64
            static let profile = hasOne(Profile.self)
        }
        """
        let model = PersistenceSchemaExtractor.extract(from: source)
        let edge = try #require(model.relationships.first)
        #expect(edge.toEntity == "Profile")
        #expect(edge.fromCardinality == .exactlyOne)
        #expect(edge.toCardinality == .zeroOrOne)
    }
}

@Suite("ERDiagramGenerator merges GRDB output with SwiftData / Core Data")
struct ERDiagramGeneratorGRDBDispatchTests {

    private func fixturePath(_ name: String) -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TestFixtures/SampleProject/Persistence")
            .appendingPathComponent(name)
            .path
    }

    @Test("GRDB Swift source produces a Mermaid erDiagram via the generator")
    func dispatchesGRDBToMermaid() throws {
        let path = fixturePath("GRDBPlayer.swift")
        var configuration = Configuration.default
        configuration.format = .mermaid
        let script = ERDiagramGenerator().generateScript(for: [path], with: configuration)
        #expect(script.text.contains("erDiagram"))
        #expect(script.text.contains("Player"))
        #expect(script.text.contains("Team"))
        #expect(script.text.contains("Score"))
    }
}
