import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

@Suite("PersistenceSchemaExtractor — SQLite.swift")
struct SchemaExtractorSQLiteSwiftTests {

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

    @Test("SQLiteSchema fixture: Table('users') becomes an entity with its Expression columns")
    func usersTableWithColumns() throws {
        let source = try String(contentsOfFile: fixturePath("SQLiteSchema.swift"), encoding: .utf8)
        let model = PersistenceSchemaExtractor.extract(from: source)
        let users = try #require(model.entities.first { $0.name == "users" })
        #expect(Set(users.attributes.map(\.name)) == ["id", "name", "email"])
        let idColumn = try #require(users.attributes.first { $0.name == "id" })
        #expect(idColumn.type == "Int64")
        #expect(idColumn.isPrimaryKey == true)
        let nameColumn = try #require(users.attributes.first { $0.name == "name" })
        #expect(nameColumn.type == "String")
    }

    @Test("schema container with multiple Tables emits each table without column attribution")
    func multipleTablesNoColumns() {
        let source = """
        enum MultiSchema {
            static let users = Table("users")
            static let posts = Table("posts")
            static let id = Expression<Int64>("id")
        }
        """
        let model = PersistenceSchemaExtractor.extract(from: source)
        #expect(Set(model.entities.map(\.name)) == ["users", "posts"])
        for entity in model.entities {
            #expect(entity.attributes.isEmpty)
        }
    }

    @Test("schema container with no Table declarations is ignored")
    func noTableMeansNoEntity() {
        let source = """
        enum HelperConstants {
            static let host = "localhost"
            static let port = 5432
        }
        """
        let model = PersistenceSchemaExtractor.extract(from: source)
        #expect(model.entities.isEmpty)
    }
}
