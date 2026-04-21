import Testing
@testable import SwiftUMLBridgeFramework

@Suite("ERModelExtractor")
struct ERModelExtractorTests {

    // MARK: - Entity discovery

    @Test("detects a single @Model class")
    func singleModelClass() {
        let source = """
        import SwiftData

        @Model
        final class Note {
            var title: String = ""
            init() {}
        }
        """
        let model = ERModelExtractor.extract(from: source)
        #expect(model.entities.count == 1)
        #expect(model.entities.first?.name == "Note")
    }

    @Test("ignores classes without @Model")
    func ignoresNonModelClasses() {
        let source = """
        final class NotAModel {
            var title: String = ""
        }
        @Model final class Real { var value: Int = 0 }
        """
        let model = ERModelExtractor.extract(from: source)
        #expect(model.entities.map(\.name) == ["Real"])
    }

    // MARK: - Attribute extraction

    @Test("extracts plain attributes with their types")
    func plainAttributes() {
        let source = """
        @Model final class Book {
            var title: String = ""
            var pageCount: Int = 0
            var publishedAt: Date = Date()
        }
        """
        let model = ERModelExtractor.extract(from: source)
        let book = model.entities.first(where: { $0.name == "Book" })
        #expect(book?.attributes.count == 3)
        #expect(book?.attributes.contains(where: { $0.name == "title" && $0.type == "String" }) == true)
        #expect(book?.attributes.contains(where: { $0.name == "pageCount" && $0.type == "Int" }) == true)
        #expect(book?.attributes.contains(where: { $0.name == "publishedAt" && $0.type == "Date" }) == true)
    }

    @Test("marks optional attributes")
    func optionalAttributes() {
        let source = """
        @Model final class Author {
            var name: String = ""
            var bio: String?
        }
        """
        let model = ERModelExtractor.extract(from: source)
        let bio = model.entities.first?.attributes.first(where: { $0.name == "bio" })
        #expect(bio?.isOptional == true)
        #expect(bio?.type == "String")
    }

    @Test("flags @Attribute(.unique) as unique and primary key")
    func uniqueAttributeIsPrimaryKey() {
        let source = """
        @Model final class User {
            @Attribute(.unique) var handle: String = ""
            var name: String = ""
        }
        """
        let model = ERModelExtractor.extract(from: source)
        let handle = model.entities.first?.attributes.first(where: { $0.name == "handle" })
        #expect(handle?.isUnique == true)
        #expect(handle?.isPrimaryKey == true)
    }

    @Test("flags bare `id` property as primary key even without @Attribute")
    func idIsPrimaryKey() {
        let source = """
        @Model final class Entry {
            var id: UUID = UUID()
            var title: String = ""
        }
        """
        let model = ERModelExtractor.extract(from: source)
        let idAttribute = model.entities.first?.attributes.first(where: { $0.name == "id" })
        #expect(idAttribute?.isPrimaryKey == true)
        #expect(idAttribute?.isUnique == false)
    }

    @Test("flags @Transient attributes")
    func transientAttributes() {
        let source = """
        @Model final class Cached {
            var name: String = ""
            @Transient var preview: String = ""
        }
        """
        let model = ERModelExtractor.extract(from: source)
        let preview = model.entities.first?.attributes.first(where: { $0.name == "preview" })
        #expect(preview?.isTransient == true)
    }

    // MARK: - Relationship extraction

    @Test("to-many property yields a zero-or-many relationship")
    func toManyRelationship() {
        let source = """
        @Model final class Author {
            @Relationship(inverse: \\Book.author)
            var books: [Book] = []
        }
        @Model final class Book {
            var title: String = ""
        }
        """
        let model = ERModelExtractor.extract(from: source)
        let relationship = model.relationships.first
        #expect(relationship?.from == "Author")
        #expect(relationship?.toEntity == "Book")
        #expect(relationship?.toCardinality == .zeroOrMany)
        #expect(relationship?.label == "books")
        #expect(relationship?.inverseLabel == "author")
    }

    @Test("optional to-one property yields a zero-or-one relationship")
    func optionalToOneRelationship() {
        let source = """
        @Model final class Profile { var handle: String = "" }
        @Model final class Book {
            @Relationship(inverse: \\Profile.book)
            var profile: Profile?
        }
        """
        let model = ERModelExtractor.extract(from: source)
        let relationship = model.relationships.first(where: { $0.from == "Book" })
        #expect(relationship?.toCardinality == .zeroOrOne)
    }

    @Test("required to-one property yields an exactly-one relationship")
    func requiredToOneRelationship() {
        let source = """
        @Model final class Country { var name: String = "" }
        @Model final class City {
            @Relationship(inverse: \\Country.capital)
            var country: Country
        }
        """
        let model = ERModelExtractor.extract(from: source)
        let relationship = model.relationships.first(where: { $0.from == "City" })
        #expect(relationship?.toCardinality == .exactlyOne)
    }

    @Test("implicit relationship is detected when target type is @Model")
    func implicitRelationshipAgainstModelType() {
        let source = """
        @Model final class A { var value: Int = 0 }
        @Model final class B {
            var ref: A?
        }
        """
        let model = ERModelExtractor.extract(from: source)
        #expect(model.relationships.count == 1)
        let relationship = model.relationships.first
        #expect(relationship?.from == "B")
        #expect(relationship?.toEntity == "A")
        #expect(relationship?.label == "ref")
    }

    @Test("implicit inverse is deduped against explicit owner")
    func implicitInverseIsDeduped() {
        let source = """
        @Model final class Author {
            @Relationship(inverse: \\Book.author)
            var books: [Book] = []
        }
        @Model final class Book {
            var author: Author?
        }
        """
        let model = ERModelExtractor.extract(from: source)
        #expect(model.relationships.count == 1)
        #expect(model.relationships.first?.label == "books")
    }

    @Test("property referring to a non-@Model type stays an attribute")
    func nonModelReferenceIsAttribute() {
        let source = """
        @Model final class Thing {
            var tag: String = ""
            var metadata: Metadata = Metadata()
        }
        struct Metadata { var count: Int = 0 }
        """
        let model = ERModelExtractor.extract(from: source)
        let thing = model.entities.first(where: { $0.name == "Thing" })
        #expect(thing?.attributes.map(\.name).sorted() == ["metadata", "tag"])
        #expect(model.relationships.isEmpty)
    }

    // MARK: - Type unwrapping

    @Test("unwrapRelationshipType handles Array<T> syntax")
    func unwrapArrayGeneric() {
        let (type, cardinality) = ERModelExtractor.unwrapRelationshipType("Array<Book>")
        #expect(type == "Book")
        #expect(cardinality == .zeroOrMany)
    }

    @Test("unwrapRelationshipType handles Set<T>")
    func unwrapSetGeneric() {
        let (type, cardinality) = ERModelExtractor.unwrapRelationshipType("Set<Tag>")
        #expect(type == "Tag")
        #expect(cardinality == .zeroOrMany)
    }

    @Test("unwrapRelationshipType handles Optional<T>")
    func unwrapOptionalGeneric() {
        let (type, cardinality) = ERModelExtractor.unwrapRelationshipType("Optional<Book>")
        #expect(type == "Book")
        #expect(cardinality == .zeroOrOne)
    }
}
