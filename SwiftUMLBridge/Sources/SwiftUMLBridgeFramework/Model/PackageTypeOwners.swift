/// The module each type name of a package belongs to, which `deps --types --package` tags both
/// ends of an edge with: the target that declares the type, or, when no target does, the first
/// that extends it. A declaration wins over any extension, whatever order they are recorded in.
/// Otherwise the first record wins, so the caller records the files in path order
/// (`sourceFilesInPathOrder`), and the answer is the same however the package lists its files.
///
/// When a type's label came from the last edge that named it, an extension in another target
/// could label the type with that target's module, and which target that was followed hash
/// order (#70).
struct PackageTypeOwners {
    private var declaring: [String: String] = [:]
    private var extending: [String: String] = [:]

    /// Records the types `item` declares as `module`'s, nested ones under their qualified names
    /// (`Outer.Inner`, as `extension Outer.Inner` and `struct X: Outer.Inner` name them), or, for
    /// an extension, `module` as one that extends the type.
    mutating func record(_ item: SyntaxStructure, in module: String) {
        guard let kind = item.kind, ElementKind.processable.contains(kind), let name = item.name else { return }
        if kind == .extension {
            extending[name] = extending[name] ?? module
        } else {
            declaring[name] = declaring[name] ?? module
        }
        recordNestedTypes(of: item, qualifiedAs: name, in: module)
    }

    /// The module that declares the type `name`, or else the first that extends it; nil for a
    /// type the package neither declares nor extends.
    func module(of name: String) -> String? {
        declaring[name] ?? extending[name]
    }

    private mutating func recordNestedTypes(of item: SyntaxStructure, qualifiedAs name: String, in module: String) {
        for child in item.substructure ?? [] {
            guard let kind = child.kind, kind != .extension, ElementKind.processable.contains(kind),
                  let childName = child.name else { continue }
            let qualified = "\(name).\(childName)"
            declaring[qualified] = declaring[qualified] ?? module
            recordNestedTypes(of: child, qualifiedAs: qualified, in: module)
        }
    }
}
