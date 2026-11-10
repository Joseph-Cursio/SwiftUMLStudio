import Foundation
import Testing

// Runs the built `swiftumlbridge` executable as a subprocess, for tests that need a real working
// directory: changing this process's would move every test running in parallel along with it.

/// Anchors `Bundle(for:)` to this test bundle. `Bundle.allBundles` does not
/// list it when Swift Testing's runner loads it.
final class TestBundleMarker {}
