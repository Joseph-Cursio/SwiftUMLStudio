import Foundation

/// The kind of a build product / component: an executable, a library, a test target, or
/// anything else.
///
/// One shared type for the SPM parser (`SPMTargetDescription.Kind`) and the UML domain model
/// (`Component.Kind`), which are nested typealiases of this enum. They were previously two
/// byte-identical enums bridged by a hand-written identity `switch` — SwiftProjectLint's
/// Parallel List Drift / Enum Shape flagged the duplication. Unifying removes the second copy
/// and the conversion, so a new kind is added in exactly one place.
public enum ComponentKind: String, Sendable, Hashable {
    case executable
    case library
    case test
    case other
}
