import Foundation

/// A type that can be uniquely identified.
public protocol Identifiable {
    var identifier: String { get }
}

/// A type that can be persisted to storage.
public protocol Persistable {
    func save() throws
    func delete() throws
}

/// A type that can validate its own state.
protocol Validatable {
    var isValid: Bool { get }

    func validate() throws
}
