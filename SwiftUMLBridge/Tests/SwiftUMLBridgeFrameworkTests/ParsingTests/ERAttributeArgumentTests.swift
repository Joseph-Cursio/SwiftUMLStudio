import Testing
@testable import SwiftUMLBridgeFramework

/// `@Attribute`'s options and `@Relationship`'s `inverse:` are read from the syntax rather than
/// searched for in the arguments' text, so a comment or a string that mentions `.unique` or a key
/// path changes nothing (#128).
@Suite("ER attribute arguments")
struct ERAttributeArgumentTests {

    @Test("an @Attribute is unique only when it lists .unique", arguments: [
        ("@Attribute(.unique)", true),
        ("@Attribute(.unique, originalName: \"c\")", true),
        ("@Attribute(.externalStorage, .`unique`)", true),
        ("@Attribute(Schema.Attribute.Option.unique)", true),
        ("@Attribute(.externalStorage, /* not .unique */ originalName: \"c\")", false),
        ("@Attribute(.externalStorage /* was .unique */)", false),
        ("@Attribute(originalName: \"legacy.unique\")", false),
        ("@Attribute(originalName: Legacy.unique)", false),
        ("@Attribute(.transformable(by: Transformers.unique))", false),
        ("@Attribute(.externalStorage)", false),
        ("@Attribute(.spotlight)", false),
        ("@Attribute(.allowsCloudEncryption, .ephemeral)", false),
        ("@Attribute", false)
    ])
    func uniqueOption(attribute: String, isUnique: Bool) {
        let attributes = ERModelExtractor.extract(from: """
            @Model final class Item {
                \(attribute) var code: String = ""
            }
            """).entities.flatMap(\.attributes)
        #expect(attributes.map(\.isUnique) == [isUnique])
    }

    /// `Book` has two properties of type `Author?`. The one `inverse:` names is the far end of
    /// `books`, and the other is a relationship of its own. The property is the key path's last
    /// component: `\MyApp.Book.writer` is parsed as the root `MyApp` with `Book` and `writer`.
    @Test("an inverse is the key path inverse: is given", arguments: [
        ("@Relationship(inverse: \\Book.writer)", ["Author.books -> Book", "Book.author -> Author"]),
        ("@Relationship(inverse: \\MyApp.Book.writer)", ["Author.books -> Book", "Book.author -> Author"]),
        ("@Relationship(inverse: \\Book.writer?)", ["Author.books -> Book", "Book.author -> Author"]),
        ("@Relationship(inverse: (\\Book.writer))", ["Author.books -> Book", "Book.author -> Author"]),
        ("@Relationship(inverse: \\Book.writer as AnyKeyPath)", ["Author.books -> Book", "Book.author -> Author"]),
        ("@Relationship(deleteRule: .cascade, inverse : \\Book.writer)",
         ["Author.books -> Book", "Book.author -> Author"]),
        ("@Relationship(inverse: /* was \\Book.author */ \\Book.writer)",
         ["Author.books -> Book", "Book.author -> Author"]),
        ("@Relationship(deleteRule: /* inverse: \\Book.writer */ .cascade)",
         ["Author.books -> Book", "Book.author -> Author", "Book.writer -> Author"]),
        ("@Relationship", ["Author.books -> Book", "Book.author -> Author", "Book.writer -> Author"])
    ])
    func inverseKeyPath(attribute: String, relationships: [String]) {
        let model = ERModelExtractor.extract(from: """
            @Model final class Author {
                \(attribute) var books: [Book] = []
            }
            @Model final class Book {
                var writer: Author?
                var author: Author?
            }
            """)
        #expect(model.relationships.map { "\($0.from).\($0.label) -> \($0.toEntity)" }.sorted() == relationships)
    }

    /// A raw identifier may hold a dot, so the property is the key path's last component, not
    /// the name after its first dot (#129).
    @Test("an inverse key path's root is one type, whatever its name holds")
    func rawIdentifierRoot() {
        let model = ERModelExtractor.extract(from: """
            @Model final class Author {
                @Relationship(inverse: \\`v1.2 Book`.author) var books: [`v1.2 Book`] = []
            }
            @Model final class `v1.2 Book` {
                var author: Author?
            }
            """)
        #expect(model.relationships.map(\.label) == ["books"])
    }
}
