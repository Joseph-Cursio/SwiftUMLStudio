import Foundation
import Synchronization

/// Runtime toggles for the Bridge framework.
///
/// Hosts running inside the macOS App Sandbox (e.g. App-Store-distributed
/// Studio builds) cannot tolerate `dlopen`-ing `sourcekitdInProc.framework`
/// from the system Xcode toolchain. Set `skipSourceKitTypenameSupplement`
/// during host start-up to keep `SyntaxStructureProvider` on the
/// SwiftSyntax-only path.
public enum BridgeConfiguration {
    /// Backing storage for ``skipSourceKitTypenameSupplement``.
    ///
    /// A `Mutex` rather than a bare `nonisolated(unsafe) static var`. The flag
    /// is written once by the host and then read from whichever task is
    /// parsing, so the unsynchronised version was a write racing an unknown
    /// number of concurrent reads — safe only by the convention that the write
    /// lands first, which nothing enforced and the compiler could not check.
    ///
    /// The lock is not on a hot path: it is taken once per file in
    /// `buildTypenameMap`, against a parse that costs orders of magnitude more.
    private static let storage = Mutex<Bool>(false)

    /// When `true`, `SyntaxStructure.create(...)` skips the SourceKit pass
    /// that resolves inferred variable typenames. Defaults to `false`. The
    /// only loss is fidelity for `let x = foo()`-style declarations whose
    /// types cannot be read from the syntax tree alone.
    ///
    /// Reads and writes are individually atomic, so setting this at any point
    /// is memory-safe. It remains a start-up decision by intent: flipping it
    /// while a generation is in flight leaves some files parsed with the
    /// supplement and some without, which is a coherence question rather than
    /// a safety one.
    public static var skipSourceKitTypenameSupplement: Bool {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }
}
