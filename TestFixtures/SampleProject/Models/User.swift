import Foundation

/// Represents a registered user in the system.
public class User: Identifiable, Validatable {
    public let identifier: String
    public var name: String
    public var email: String
    private var passwordHash: String

    public init(identifier: String, name: String, email: String, passwordHash: String) {
        self.identifier = identifier
        self.name = name
        self.email = email
        self.passwordHash = passwordHash
    }

    var isValid: Bool {
        !name.isEmpty && email.contains("@")
    }

    func validate() throws {
        try self.checkEmailFormat()
        try self.checkPasswordHash()
        guard isValid else {
            throw ValidationError.invalidUser
        }
    }

    func checkEmailFormat() throws {
        guard email.contains("@") else {
            throw ValidationError.invalidEmail
        }
    }

    func checkPasswordHash() throws {
        guard !passwordHash.isEmpty else {
            throw ValidationError.weakPassword
        }
    }
}

/// A user with elevated permissions.
public class AdminUser: User {
    public var permissions: Set<Permission>

    public init(identifier: String, name: String, email: String, passwordHash: String, permissions: Set<Permission>) {
        self.permissions = permissions
        super.init(identifier: identifier, name: name, email: email, passwordHash: passwordHash)
    }

    public func canPerform(_ action: Permission) -> Bool {
        permissions.contains(action)
    }
}

/// Available admin permissions.
public enum Permission: String, CaseIterable {
    case readUsers
    case writeUsers
    case deleteUsers
    case manageRoles
}

/// Validation errors.
enum ValidationError: Error {
    case invalidUser
    case invalidEmail
    case weakPassword
}
