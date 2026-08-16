import Testing
@testable import SwiftUMLBridgeFramework

@Suite("BridgeConfiguration", .serialized)
struct BridgeConfigurationTests {

    @Test("skipSourceKitTypenameSupplement defaults to false")
    func defaultsToFalse() {
        #expect(BridgeConfiguration.skipSourceKitTypenameSupplement == false)
    }

    /// Hammers the accessors from many tasks at once. The value written is
    /// always `false`, which is both the default and what every other suite
    /// expects, so this contends the lock without changing what a concurrently
    /// running parse observes.
    ///
    /// Under the previous `nonisolated(unsafe) static var` this was a write
    /// racing concurrent reads. It cannot deadlock or tear now; a regression
    /// that reintroduced the race would need TSan to prove, but a broken
    /// accessor or a lock taken re-entrantly would hang or trap right here.
    @Test("concurrent reads and writes are safe")
    func concurrentAccess() async {
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<200 {
                group.addTask { BridgeConfiguration.skipSourceKitTypenameSupplement }
                group.addTask {
                    BridgeConfiguration.skipSourceKitTypenameSupplement = false
                    return BridgeConfiguration.skipSourceKitTypenameSupplement
                }
            }

            for await observed in group {
                #expect(observed == false)
            }
        }

        #expect(BridgeConfiguration.skipSourceKitTypenameSupplement == false)
    }

    // Deliberately not tested here: setting the flag to `true` and observing
    // that `buildTypenameMap` returns an empty map. The flag is process-global
    // and the suite runs in parallel, so flipping it — even briefly, even
    // restored in a `defer` — would strip the typename supplement from
    // whichever parse happened to be running, producing a failure with no
    // relation to the test that caused it. The `true` path is exercised by the
    // APP_STORE_BUILD configuration, which sets it once at launch.
}
