import Testing
@testable import SwiftUMLBridgeFramework

/// `` `Pet` `` and `Pet` are one identifier, so a name escaped where it is declared and not where it
/// is used, or the other way round, is still one name to the ER, state-machine, GRDB / SQLite.swift
/// and import extractors. Each witness must read as the same source with its backticks removed. A
/// raw identifier (`` `Pet Owner` ``) or a keyword (`` `default` ``) keeps its backticks (#123).
@Suite("Canonical names in the ER, state-machine and import extractors")
struct ERStateImportCanonicalNameTests {

    /// The witness with every backtick removed: the same program, spelt without escapes.
    private static func unescaped(_ source: String) -> String {
        source.replacingOccurrences(of: "`", with: "")
    }

    private static func mermaid(_ model: ERModel) -> String {
        var configuration = Configuration.default
        configuration.format = .mermaid
        return ERScript(model: model, configuration: configuration).text
    }

    // MARK: - Witnesses: a name escaped on one side only

    @Test("a SwiftData name escaped on one side reads as the source without backticks",
          arguments: Witnesses.swiftData)
    func swiftDataWitness(source: String) {
        let control = ERModelExtractor.extract(from: Self.unescaped(source))
        #expect(!control.relationships.isEmpty)
        #expect(ERModelExtractor.extract(from: source) == control)
    }

    @Test("an entity escaped where it is declared is the end of the to-many property that names it")
    func ownerAndPetDiagram() {
        let expected = """
        erDiagram
            Owner ||--o{ Pet : pets
            Pet }o--o| Owner : owner
            Owner {
            }
            Pet {
                String name
            }
        """
        #expect(Self.mermaid(ERModelExtractor.extract(from: Witnesses.ownerAndPet)) == expected)
        #expect(Self.mermaid(ERModelExtractor.extract(from: Self.unescaped(Witnesses.ownerAndPet))) == expected)
    }

    @Test("a state machine name escaped on one side reads as the source without backticks",
          arguments: Witnesses.stateMachines)
    func stateMachineWitness(source: String) {
        let control = StateMachineExtractor.extract(from: Self.unescaped(source))
        #expect(!control.isEmpty)
        #expect(StateMachineExtractor.extract(from: source) == control)
    }

    @Test("a GRDB or SQLite.swift name escaped on one side reads as the source without backticks",
          arguments: Witnesses.persistence)
    func persistenceWitness(source: String) {
        let control = PersistenceSchemaExtractor.extract(from: Self.unescaped(source))
        #expect(!control.entities.isEmpty)
        #expect(PersistenceSchemaExtractor.extract(from: source) == control)
    }

    @Test("an escaped module path reads as the path without backticks")
    func importWitness() {
        let source = "import `Foundation`\nimport struct `Foundation`.`URL`\nimport Swift"
        let modules = ImportExtractor.extract(from: source, sourceModule: "App").map(\.importedModule)
        #expect(modules == ["Foundation", "Foundation.URL", "Swift"])
    }

    // MARK: - Controls: names that need their backticks keep them

    @Test("a raw identifier or keyword entity, property and inverse keep their backticks")
    func swiftDataControl() throws {
        let source = """
        import SwiftData

        @Model final class `Pet Owner` {
            @Relationship(inverse: \\`class`.`default`) var pets: [`class`] = []
            init() {}
        }

        @Model final class `class` {
            var `default`: `Pet Owner`?
            init() {}
        }
        """
        let model = ERModelExtractor.extract(from: source)
        #expect(model.entities.map(\.name) == ["`Pet Owner`", "`class`"])
        let relationship = try #require(model.relationships.first)
        #expect(model.relationships.count == 1)
        #expect(relationship.from == "`Pet Owner`")
        #expect(relationship.toEntity == "`class`")
        #expect(relationship.inverseLabel == "`default`")
    }

    @Test("a raw identifier or keyword enum, case, property and trigger keep their backticks")
    func stateMachineControl() throws {
        let source = """
        enum `Signal Light` { case `default`, `go now` }

        final class Lamp {
            var `class`: `Signal Light` = .`default`

            func `run now`() {
                switch self.`class` {
                case .`default`: self.`class` = .`go now`
                case .`go now`: self.`class` = .`default`
                }
            }
        }
        """
        let model = try #require(StateMachineExtractor.extract(from: source).first)
        #expect(model.identifier == "Lamp.`Signal Light`")
        #expect(model.states.map(\.name) == ["`default`", "`go now`"])
        #expect(model.transitions.map { "\($0.from) -> \($0.toState) : \($0.trigger ?? "")" } == [
            "`default` -> `go now` : `run now`", "`go now` -> `default` : `run now`"
        ])
    }

    @Test("a raw identifier or keyword record, column and association keep their backticks")
    func persistenceControl() throws {
        let source = """
        struct `Old Team`: TableRecord {
            var `default`: Int64?
            static let `class` = hasMany(`Old Player`.self)
        }

        struct `Old Player`: TableRecord {
            var `Foo Bar`: `Old Team`?
        }

        enum Store {
            static let things = Table("things")
            static let kind = Expression<`Old Team`>("kind")
        }
        """
        let model = PersistenceSchemaExtractor.extract(from: source)
        #expect(model.entities.map(\.name) == ["`Old Team`", "`Old Player`", "things"])
        #expect(model.entities.flatMap(\.attributes).map { "\($0.name): \($0.type)" } == [
            "`default`: Int64", "`Foo Bar`: `Old Team`", "kind: `Old Team`"
        ])
        let relationship = try #require(model.relationships.first)
        #expect(relationship.toEntity == "`Old Player`")
        #expect(relationship.label == "`class`")
    }

    @Test("a raw identifier module keeps its backticks")
    func importControl() {
        // `My Module` is not a module, so this does not compile; it only checks the parse.
        let source = "import Foundation\nimport `My Module`"
        let modules = ImportExtractor.extract(from: source, sourceModule: "App").map(\.importedModule)
        #expect(modules == ["Foundation", "`My Module`"])
    }
}

/// Sources that escape a name on one side only. Each compiles: the GRDB and SQLite.swift ones
/// against stubs of the protocols, functions and types they name.
private enum Witnesses {
    static let ownerAndPet = """
    import SwiftData

    @Model final class Owner {
        var pets: [Pet] = []
        init() {}
    }

    @Model final class `Pet` {
        var name: String = ""
        var owner: Owner?
        init() {}
    }
    """

    static let swiftData = [
        ownerAndPet,
        """
        import SwiftData

        @Model final class Owner {
            var pets: [`Pet`] = []
            init() {}
        }

        @Model final class Pet {
            var `name`: String = ""
            var owner: `Owner`?
            init() {}
        }
        """,
        """
        import Foundation
        import SwiftData

        @`Model` final class Author {
            @`Relationship`(inverse: \\Book.`author`) var books: [Book] = []
            @`Attribute`(.unique) var code: String = ""
            @`Transient` var draft: Bool = false
            var `tag` = `UUID`()
            init() {}
        }

        @Model final class Book {
            var author: Author?
            init() {}
        }
        """,
        """
        import SwiftData

        @Model final class Author {
            @Relationship(inverse: \\`Book`.author) var books: [Book] = []
            init() {}
        }

        @Model final class Book {
            var `author`: Author?
            init() {}
        }
        """
    ]

    static let stateMachines = [
        """
        enum `Light` { case red, green }

        final class Lamp {
            var state: Light = .red

            func toggle() {
                switch self.state {
                case .red: self.state = .green
                case .green: self.state = .red
                }
            }
        }
        """,
        """
        enum Light { case red, green }

        final class Lamp {
            var state: `Light` = .red

            func toggle() {
                switch self.state {
                case .red: self.state = .green
                case .green: self.state = .red
                }
            }
        }

        final class Torch {
            var state = `Light`.green

            func toggle() {
                switch state {
                case .red: state = .green
                case .green: state = .red
                }
            }
        }
        """,
        """
        enum Light { case `red`, green, done }

        final class Lamp {
            var `state`: Light = .red

            func `toggle`() {
                switch self.state {
                case .red: self.`state` = .green
                case .`green`: `state` = .`red`
                case .done: break
                }
            }

            func finish() { state = .`done` }
        }
        """
    ]

    static let persistence = [
        """
        struct Team: TableRecord {
            var id: Int64?
            static let players = hasMany(Player.self)
        }

        struct `Player`: FetchableRecord, TableRecord {
            var `id`: `Int64`?
            var name: String
            static let team = `belongsTo`(`Team`.self)
        }

        struct Score: `PersistableRecord` {
            var points: Int
        }
        """,
        """
        enum Schema {
            static let users = `Table`("users")
            static let id = Expression<`Int64`>("id")
            static let name = `Expression`<String>("name")
        }
        """
    ]
}
