import Foundation
import SwiftData

/// A SwiftData `@Model` representing the author of one or more books.
///
/// Uses `@Attribute(.unique)` to mark a stable business-key identifier and
/// `@Relationship` with an explicit inverse so the ER extractor can pair this
/// relationship with `Book.author`.
@Model
final class Author {
    @Attribute(.unique) var identifier: UUID
    var name: String
    var bio: String?

    @Relationship(deleteRule: .cascade, inverse: \Book.author)
    var books: [Book] = []

    init(identifier: UUID = UUID(), name: String, bio: String? = nil) {
        self.identifier = identifier
        self.name = name
        self.bio = bio
    }
}

/// A SwiftData `@Model` representing a book, owned by one `Author` and
/// connected to any number of `Tag` values via the `tags` relationship.
///
/// `author` has no explicit `@Relationship` — the ER extractor must infer
/// it from the property type (a known `@Model` class). `cachedPreview`
/// is marked `@Transient` so the ER extractor can flag it as non-persisted.
@Model
final class Book {
    @Attribute(.unique) var isbn: String
    var title: String
    var publishedAt: Date
    var pageCount: Int

    var author: Author?

    @Relationship(deleteRule: .noAction, inverse: \Tag.books)
    var tags: [Tag] = []

    @Transient
    var cachedPreview: String = ""

    init(isbn: String, title: String, publishedAt: Date, pageCount: Int) {
        self.isbn = isbn
        self.title = title
        self.publishedAt = publishedAt
        self.pageCount = pageCount
    }
}

/// A SwiftData `@Model` for a reusable tag applied to any number of books.
///
/// The `books` property has no explicit `@Relationship` attribute — the
/// extractor must dedupe it against `Book.tags`, which declares the inverse.
@Model
final class Tag {
    var name: String
    var books: [Book] = []

    init(name: String) {
        self.name = name
    }
}
