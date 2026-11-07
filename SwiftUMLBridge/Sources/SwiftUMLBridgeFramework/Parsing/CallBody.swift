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
    /// Its parameters, which tell the overload a call means.
    let parameters: [CallParameter]
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

/// A function's parameter, as a call's argument labels are matched to it.
struct CallParameter: Sendable, Hashable {
    /// The argument label, `_` for none.
    let label: String
    let hasDefault: Bool
    let isVariadic: Bool

    /// Whether a call with argument `labels` can mean a function with `parameters`: each label in
    /// order, where a parameter with a default may be left out, and a variadic one takes none or
    /// several arguments, the first written with its label and the rest with none.
    static func accepts(_ parameters: [CallParameter], labels: [String]) -> Bool {
        var index = 0
        for parameter in parameters {
            let isWritten = index < labels.count && labels[index] == parameter.label
            if parameter.isVariadic {
                guard isWritten else { continue }
                index += 1
                while index < labels.count, labels[index] == "_" { index += 1 }
            } else if isWritten {
                index += 1
            } else if !parameter.hasDefault {
                return false
            }
        }
        return index == labels.count
    }

    /// Of `bodies`, those a call with argument `labels` can mean, so `load()` does not reach
    /// `load(_:)`. All of them when the labels are not known, as with a trailing closure, or when
    /// none matches, so a call this cannot match still reaches what it did.
    static func narrowed(_ bodies: [CallBody], to labels: [String]?) -> [CallBody] {
        guard let labels, bodies.count > 1 else { return bodies }
        let matching = bodies.filter { accepts($0.parameters, labels: labels) }
        return matching.isEmpty ? bodies : matching
    }
}
