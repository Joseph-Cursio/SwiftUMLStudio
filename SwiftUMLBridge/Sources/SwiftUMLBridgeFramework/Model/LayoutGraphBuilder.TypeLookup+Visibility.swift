// MARK: - Visibility

// Which declarations a name can see as Swift's access control allows, kept apart so the type
// lookup stays a readable size. An extension of `TypeLookup` in another file does not see the
// builder's own names, so they are written out in full.
extension LayoutGraphBuilder.TypeLookup {
    /// Whether a name written in `lookup` can mean `declared`, as Swift's access control
    /// allows: a `private` or `fileprivate` type only in its own file, and a type below
    /// `package` only in its own module. A file or module that is unknown on either side is
    /// taken to be the same; parsed sources always carry a file path.
    func isVisible(
        _ declared: LayoutGraphBuilder.Declared, from lookup: LayoutGraphBuilder.Scope, depth: Int
    ) -> Bool {
        if lookup.filePath == nil || declared.scope.filePath == nil || lookup.filePath == declared.scope.filePath {
            return true
        }
        var required = ElementAccessibility.internal
        if let module = lookup.module, let own = declared.scope.module, module != own { required = .package }
        // `access(of:)` only lowers `ownAccess`, so a type its own access already hides needs no
        // lookup of the type its extension extends. That lookup walks every declaration of the
        // name, and doing it for each of many same-named private types was cubic in their number.
        return declared.ownAccess >= required && access(of: declared, depth: depth) >= required
    }

    /// `declared`'s access, capped by the access of the type its enclosing extension extends,
    /// as that extension's own lookup finds it. Each step resolves a shorter name, so this
    /// ends; the depth guard is a backstop.
    func access(of declared: LayoutGraphBuilder.Declared, depth: Int) -> ElementAccessibility {
        guard depth < 8, let type = enclosingExtensionType(of: declared, depth: depth) else {
            return declared.ownAccess
        }
        return min(declared.ownAccess, access(of: type, depth: depth + 1))
    }

    /// The type `declared`'s enclosing extension extends, as that extension's own lookup finds
    /// it at `depth + 1`, or `nil` for none. It depends on the declaration alone, so it is
    /// worked out once: `access(of:depth:)` and `isInExtensionOfOutsideType(_:depth:)` ask it
    /// of every candidate of a name, and each answer is a lookup of its own.
    func enclosingExtensionType(
        of declared: LayoutGraphBuilder.Declared, depth: Int
    ) -> LayoutGraphBuilder.Declared? {
        guard let extended = declared.extended else { return nil }
        return enclosingTypes.type(of: declared.declaration, depth: depth) {
            extendedType(
                named: extended.name, from: extended.scope, isSugared: extended.isSugared, depth: depth + 1
            )
        }
    }
}
