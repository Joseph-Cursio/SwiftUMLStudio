extension ElementKind {
    /// The declaration kinds the diagram and graph passes render as nodes — the type-like
    /// declarations. Single source of truth for the three passes (layout graph, dependency graph,
    /// diagram script), which each previously carried their own copy of this list. The copies had
    /// drifted: the dependency-graph pass was missing `.macro`, so macros were silently dropped
    /// from dependency diagrams while appearing in the others. Deriving all three from one constant
    /// makes that impossible.
    static let processable: [ElementKind] = [
        .class, .struct, .extension, .enum, .protocol, .actor, .macro
    ]
}
