/// In which builds an attribute that limits who sees a declaration applies: never, in some
/// builds, as one for a platform alone or under an `#if`, or in every build.
enum AttributeReach: Comparable, Sendable {
    case never
    case someBuilds
    case everyBuild
}
