import Testing
@testable import SwiftUMLBridgeFramework

/// SwiftData's `@Model` macro stores a class's stored instance properties, except `@Transient`
/// ones. Of stacked attributes it reads only the first `@Attribute` and the first
/// `@Relationship`. The ER reader draws what SwiftData stores (#140).
@Suite("The ER reader draws only what SwiftData stores")
struct ERStoredPropertyTests {

    private func flags(_ attributes: String, name: String = "code") -> [String] {
        ERModelExtractor.extract(from: """
            @Model final class Country {
                \(attributes) var \(name): String = ""
            }
            """).entities.flatMap(\.attributes)
            .map { "\($0.name) unique=\($0.isUnique) pk=\($0.isPrimaryKey) transient=\($0.isTransient)" }
    }

    @Test("a computed or static property is not stored, an observed one is")
    func computedAndStaticAreNotStored() {
        let model = ERModelExtractor.extract(from: """
            @Model final class Owner {
                static let defaultName: String = "Unnamed"
                static var count = Counter()
                class var kind: String { "owner" }
                var name: String = ""
                var nickname: String = "" {
                    didSet { print(nickname) }
                }
                var title: String = "" {
                    willSet { print(newValue) }
                    didSet { print(title) }
                }
                var display: String { name.uppercased() }
                var rename: String {
                    get { name }
                    set { name = newValue }
                }
                var favorite: Pet? { nil }
                var pets: [Pet] = []
            }
            @Model final class Pet {}
            """)
        let relationships = model.relationships.map { "\($0.from).\($0.label) -> \($0.toEntity)" }
        let listed = model.entities.flatMap { entity in entity.attributes.map { "\(entity.name).\($0.name)" } }
        #expect(relationships == ["Owner.pets -> Pet"])
        #expect(listed == ["Owner.name", "Owner.nickname", "Owner.title"])
    }

    @Test("a closure initializer is not an accessor block")
    func closureInitializerIsKept() {
        let listed = ERModelExtractor.extract(from: """
            @Model final class Owner {
                @Transient var make: () -> Int = { 1 }
            }
            """).entities.flatMap(\.attributes).map { "\($0.name) transient=\($0.isTransient)" }
        #expect(listed == ["make transient=true"])
    }

    @Test("a @Transient property is not a relationship", arguments: [
        "@Transient",
        "@Transient @Relationship(deleteRule: .cascade)",
        "@Relationship(deleteRule: .cascade) @Transient"
    ])
    func transientIsNotARelationship(attributes: String) {
        let model = ERModelExtractor.extract(from: """
            @Model final class Owner {
                \(attributes) var recent: [Pet] = []
            }
            @Model final class Pet {}
            """)
        let relationships = model.relationships.map { "\($0.from).\($0.label) -> \($0.toEntity)" }
        let listed = model.entities.flatMap { entity in
            entity.attributes.map { "\(entity.name).\($0.name) transient=\($0.isTransient)" }
        }
        #expect(relationships == [])
        #expect(listed == ["Owner.recent transient=true"])
    }

    @Test("a @Transient property is not unique, whatever @Attribute says", arguments: [
        "@Transient @Attribute(.unique)",
        "@Attribute(.unique) @Transient"
    ])
    func transientIsNotUnique(attributes: String) {
        #expect(flags(attributes) == ["code unique=false pk=false transient=true"])
    }

    @Test("a @Transient id is not a key")
    func transientIdIsNotAKey() {
        #expect(flags("@Transient", name: "id") == ["id unique=false pk=false transient=true"])
        #expect(flags("", name: "id") == ["id unique=false pk=true transient=false"])
    }

    @Test("only the first @Attribute's options count", arguments: [
        ("@Attribute(.spotlight) @Attribute(.unique)", false),
        ("@Attribute(.unique) @Attribute(.spotlight)", true),
        ("@Attribute(.spotlight, .unique)", true)
    ])
    func firstAttributeWins(attributes: String, unique: Bool) {
        #expect(flags(attributes) == ["code unique=\(unique) pk=\(unique) transient=false"])
    }

    /// `@Model`'s metadata keeps only the first `@Relationship`, so the second one's `inverse:`
    /// pairs nothing. (At run time SwiftData can still infer a lone inverse; that is not drawn.)
    @Test("only the first @Relationship's inverse counts", arguments: [
        ("@Relationship(deleteRule: .cascade) @Relationship(inverse: \\Book.writer)",
         ["Author.books -> Book", "Book.writer -> Author"]),
        ("@Relationship(inverse: \\Book.writer) @Relationship(deleteRule: .cascade)",
         ["Author.books -> Book"]),
        ("@Relationship(deleteRule: .cascade)", ["Author.books -> Book", "Book.writer -> Author"])
    ])
    func firstRelationshipWins(attributes: String, expected: [String]) {
        let relationships = ERModelExtractor.extract(from: """
            @Model final class Author {
                \(attributes) var books: [Book] = []
            }
            @Model final class Book {
                var writer: Author?
            }
            """).relationships.map { "\($0.from).\($0.label) -> \($0.toEntity)" }
        #expect(relationships == expected)
    }
}
