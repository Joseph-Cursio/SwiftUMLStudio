import Foundation

/// A document that can be saved and versioned, and moves through a
/// review workflow tracked by `DocumentStatus`.
public struct Document: Identifiable, Persistable {
    public let identifier: String
    public var title: String
    public var content: String
    public var version: Int
    public let createdAt: Date
    public var status: DocumentStatus

    public init(identifier: String, title: String, content: String) {
        self.identifier = identifier
        self.title = title
        self.content = content
        self.version = 1
        self.createdAt = Date()
        self.status = .draft
    }

    public func save() throws {
        // Persist to storage
    }

    public func delete() throws {
        // Remove from storage
    }

    public mutating func updateContent(_ newContent: String) {
        content = newContent
        version += 1
    }

    public mutating func submitForReview() {
        switch self.status {
        case .draft:
            self.status = .review
        default:
            break
        }
    }

    public mutating func approve() {
        switch self.status {
        case .review:
            self.status = .approved
        default:
            break
        }
    }

    public mutating func publish() {
        switch self.status {
        case .approved:
            self.status = .published
        default:
            break
        }
    }

    public mutating func archive() {
        switch self.status {
        case .draft, .review, .approved, .published:
            self.status = .archived
        case .archived:
            break
        }
    }
}

/// The status of a document in a review workflow.
public enum DocumentStatus: String {
    case draft
    case review
    case approved
    case published
    case archived
}
