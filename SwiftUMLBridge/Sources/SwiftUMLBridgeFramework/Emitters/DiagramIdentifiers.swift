/// Hands out one diagram identifier per distinct name.
///
/// The sanitizers that turn a name into an identifier — `DepsScript.mermaidId`,
/// `ComponentScript.safeAlias` — map several characters to `_`, so two different
/// names can sanitize alike: `Outer.Inner` and `Outer_Inner` both give `Outer_Inner`.
/// An emitter that used the sanitized text directly declared both names under one
/// identifier, and the renderer drew them as a single node carrying both sets of edges.
///
/// The first name to claim an identifier keeps it, so a diagram with no collision is
/// unchanged; a later name that collides gets `_2`, `_3`, …. Names are claimed in the
/// order the emitter asks, so an emitter that walks its model deterministically gets
/// deterministic identifiers.
struct DiagramIdentifiers {
    private let sanitize: (String) -> String
    private var byKey: [String: String] = [:]
    private var taken: Set<String> = []

    init(sanitize: @escaping (String) -> String) {
        self.sanitize = sanitize
    }

    /// The identifier for `name`, claiming one on first use.
    mutating func id(for name: String) -> String {
        id(forKey: name, sanitizing: name)
    }

    /// The identifier for `key`, built from `text` on first use. For a node whose
    /// identity is not its text alone — a provided interface is keyed by its component
    /// and its own name, and must not share an identifier with a component whose name
    /// happens to sanitize the same way.
    mutating func id(forKey key: String, sanitizing text: String) -> String {
        if let existing = byKey[key] {
            return existing
        }
        let base = sanitize(text)
        var candidate = base
        var suffix = 2
        while taken.contains(candidate) {
            candidate = "\(base)_\(suffix)"
            suffix += 1
        }
        byKey[key] = candidate
        taken.insert(candidate)
        return candidate
    }
}
