import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// `@SwiftData.Model` is SwiftData's `@Model` written with its module, and the compiler applies the
/// same macro to it. The same holds for `@Observation.Observable`, `GRDB.FetchableRecord` and
/// `SQLite.Expression`. Each test runs its source with the module written (`qualified → true`) and
/// with it removed (`qualified → false`). The second case is the control.
@Suite("A persistence or Observation name written with its module is still that name")
struct ModuleQualifiedAttributeTests {
    private func source(_ text: String, qualified: Bool) -> String {
        qualified ? text : text.replacingOccurrences(
            of: #"\b(SwiftData|Observation|GRDB|SQLite)\."#, with: "", options: .regularExpression)
    }

    @Test("@SwiftData.Model marks an entity", arguments: [true, false])
    func qualifiedModel(qualified: Bool) {
        let model = ERModelExtractor.extract(from: source("""
            @SwiftData.Model final class Owner {
                var name: String = ""
                @Relationship(deleteRule: .cascade, inverse: \\Pet.owner) var pets: [Pet] = []
            }
            @Model final class Pet {
                @Attribute(.unique) var tag: String = ""
                var owner: Owner?
            }
            """, qualified: qualified))
        let entities = model.entities.map { "\($0.name)(\($0.attributes.map(\.name).joined(separator: ", ")))" }
        let relationships = model.relationships.map { "\($0.from).\($0.label) -> \($0.toEntity)" }
        #expect(entities == ["Owner(name)", "Pet(tag)"])
        #expect(relationships == ["Owner.pets -> Pet"])
    }

    @Test("@SwiftData.Model and @Observation.Observable draw their conformance edges",
          arguments: [DiagramFormat.plantuml, .mermaid], [true, false])
    func qualifiedMacroConformances(format: DiagramFormat, qualified: Bool) {
        let script = ClassDiagramGenerator().generateScript(for: source("""
            @SwiftData.Model final class Item {}
            @Observation.Observable final class Counter {}
            """, qualified: qualified), with: Configuration(format: format)).text
        let edges = script.split(separator: "\n").map(String.init).filter { $0.contains("<|--") }
        #expect(edges == [
            "Observable <|-- Item : inherits",
            "PersistentModel <|-- Item : inherits",
            "Observable <|-- Counter : inherits"
        ])
    }

    @Test("a GRDB record protocol written with its module marks a record", arguments: [true, false])
    func qualifiedGRDBRecord(qualified: Bool) {
        let entities = PersistenceSchemaExtractor.extract(from: source("""
            struct Player: GRDB.FetchableRecord, GRDB.PersistableRecord {
                var id: Int64
                var name: String
            }
            """, qualified: qualified)).entities.map(\.name)
        #expect(entities == ["Player"])
    }

    @Test("SQLite.Expression<T> written with its module is a column", arguments: [true, false])
    func qualifiedSQLiteExpression(qualified: Bool) {
        let entities = PersistenceSchemaExtractor.extract(from: source("""
            enum Schema {
                static let users = SQLite.Table("users")
                static let id = SQLite.Expression<Int64>("id")
                static let email = SQLite.Expression<String>("email")
            }
            """, qualified: qualified)).entities
        let columns = entities.flatMap { entity in entity.attributes.map { "\(entity.name).\($0.name): \($0.type)" } }
        #expect(columns == ["users.id: Int64", "users.email: String"])
    }

    // MARK: - Spellings of the module

    @Test("the module may be written with backticks, spaces or a line break", arguments: [
        "@`SwiftData`.`Model`",
        "@SwiftData . Model",
        "@SwiftData\n    .Model"
    ])
    func moduleSpellings(attribute: String) {
        let entities = ERModelExtractor.extract(from: """
            \(attribute) final class Owner {
                var name: String = ""
            }
            """).entities.map(\.name)
        #expect(entities == ["Owner"])
    }

    @Test("a backticked @`SwiftData`.`Model` draws its conformance edges")
    func backtickedConformances() {
        let script = ClassDiagramGenerator().generateScript(
            for: "@`SwiftData`.`Model` final class Item {}", with: Configuration(format: .plantuml)
        ).text
        let edges = script.split(separator: "\n").map(String.init).filter { $0.contains("<|--") }
        #expect(edges == ["Observable <|-- Item : inherits", "PersistentModel <|-- Item : inherits"])
    }

    @Test("Nomnoml draws the conformance edges of a qualified macro")
    func nomnomlConformances() {
        let script = ClassDiagramGenerator().generateScript(
            for: "@SwiftData.Model final class Item {}", with: Configuration(format: .nomnoml)
        ).text
        #expect(script.contains("[Item] -:> inherits [Observable]"), "\(script)")
        #expect(script.contains("[Item] -:> inherits [PersistentModel]"), "\(script)")
    }

    @Test("a GRDB record protocol written with its module counts inside a composition")
    func qualifiedGRDBComposition() {
        let entities = PersistenceSchemaExtractor.extract(from: """
            struct Player: Codable, GRDB.FetchableRecord & GRDB.PersistableRecord {
                var id: Int64
            }
            """).entities.map(\.name)
        #expect(entities == ["Player"])
    }

    // MARK: - Guards: a fix must keep these passing.

    /// SwiftData's own `@Model` expansion does not read `@SwiftData.Attribute(.unique)`,
    /// `@SwiftData.Transient` or `@SwiftData.Relationship(…)` on a member: it gives the property
    /// `metadata: nil` and persists it (observed with `-dump-macro-expansions`, Swift 6.4).
    @Test("a member attribute written with its module is read as SwiftData's @Model reads it")
    func qualifiedMemberAttributes() {
        let flags = ERModelExtractor.extract(from: """
            @SwiftData.Model final class Item {
                @SwiftData.Attribute(.unique) var code: String = ""
                @SwiftData.Transient var cache: String = ""
            }
            """).entities.flatMap(\.attributes).map { "\($0.name) unique=\($0.isUnique) transient=\($0.isTransient)" }
        #expect(flags == ["code unique=false transient=false", "cache unique=false transient=false"])
    }

    /// A `Model` from another module, here a global actor, is not SwiftData's.
    @Test("@MyKit.Model is not SwiftData's @Model, nor @MyKit.Observable Observation's")
    func otherModulesModel() {
        let text = """
            @MyKit.Model final class Item { var title: String = "" }
            @MyKit.Observable final class Counter {}
            @SwiftData.Observable final class Gauge {}
            """
        let entities = ERModelExtractor.extract(from: text).entities.map(\.name)
        let edges = ClassDiagramGenerator().generateScript(for: text, with: Configuration(format: .plantuml)).text
            .split(separator: "\n").filter { $0.contains("<|--") }
        #expect(entities.isEmpty)
        #expect(edges.isEmpty)
    }

    @Test("a record protocol from another module is not GRDB's")
    func otherModulesRecord() {
        let entities = PersistenceSchemaExtractor.extract(from: """
            struct Player: MyKit.FetchableRecord, Outer.GRDB.PersistableRecord {
                var id: Int64
            }
            """).entities.map(\.name)
        #expect(entities.isEmpty)
    }

    @Test("the stereotype keeps the module as written")
    func stereotypeKeepsModule() {
        let script = ClassDiagramGenerator().generateScript(
            for: "@SwiftData.Model final class Item {}", with: Configuration(format: .plantuml)
        ).text
        #expect(script.contains("<<SwiftData.Model>>"), "\(script)")
    }
}
