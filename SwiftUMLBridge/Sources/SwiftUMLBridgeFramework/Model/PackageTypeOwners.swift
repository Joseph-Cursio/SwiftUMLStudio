/// The first module that extends each type name of a package, which `deps --types --package`
/// tags an edge end with when the writer's file sees no project type of that name: a type outside
/// the package, as Swift's `String`, which only an extension can tag. Every other end takes the
/// module of the declaration the class diagram ends it on (#202). The first record wins, so the
/// caller records the files in path order (`sourceFilesInPathOrder`), and the answer is the same
/// however the package lists its files.
///
/// When a type's label came from the last edge that named it, an extension in another target
/// could label the type with that target's module, and which target that was followed hash
/// order (#70).
struct PackageTypeOwners {
    private var extending: [String: String] = [:]

    /// Records `module` as one that extends the type `item` names, when `item` is an extension.
    mutating func record(_ item: SyntaxStructure, in module: String) {
        guard item.kind == .extension, let name = item.name else { return }
        extending[name] = extending[name] ?? module
    }

    /// The first module that extends the type `name`; nil for a type the package does not extend.
    func extendingModule(of name: String) -> String? {
        extending[name]
    }
}
