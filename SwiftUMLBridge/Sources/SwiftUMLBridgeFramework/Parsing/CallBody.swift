import Foundation

/// One function body the call graph files calls under, told apart from every other body filed
/// under the same `Type.method`: an overload, a same-named type's method, and a function or type
/// local to a body all share that name (#235).
struct CallBody: Sendable, Hashable {
    /// The file it is in, and where its declaration starts there in UTF-8 bytes, which together
    /// tell it from every other body.
    let file: URL?
    let offset: Int
    /// The innermost type around it, which its calls are filed under (`typeStack.last`).
    let type: String
    /// Every type around it, outermost first, joined with `.`: `OB.IB` for a method in `IB`'s
    /// body inside `OB`, and an extension's name as it is filed.
    let path: String
    /// How many types are around it: 1 for a top-level type's body or an extension.
    let depth: Int
    let method: String
    /// Whether `Type.method` can name it from outside a body: a member, of a type that is not
    /// local to a body. Only such a body can be an entry, or be reached by a call through its name.
    let isNameable: Bool
    /// The type local to a body that it is a member of (`identifier(file:offset:)`), when it is
    /// one: a call inside that type's members to `self` reaches only that type's members.
    let localType: String?

    var identifier: String { Self.identifier(file: file, offset: offset) }

    /// What tells a declaration from every other: its file and where it starts.
    static func identifier(file: URL?, offset: Int) -> String {
        "\(file?.path ?? ""):\(offset)"
    }
}
