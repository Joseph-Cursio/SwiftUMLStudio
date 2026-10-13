import Foundation
import Testing
@testable import SwiftUMLStudio

/// The preference-store tests run on ``InMemoryKeyValueStore``, so it has to answer like the
/// `UserDefaults` the app passes. Each test runs once against each.
@Suite("KeyValueStore")
struct KeyValueStoreTests {

    enum Backing: CaseIterable {
        case inMemory
        case userDefaults

        /// The `UserDefaults` side uses one fixed suite with fresh keys, rather than a fresh suite:
        /// cfprefsd keeps an empty plist for every suite ever written, so a suite per run would
        /// add a file to `~/Library/Preferences` each time. This way there is only ever one.
        static let suiteName = "name.JosephCursio.SwiftUMLStudio.UnitTests"

        func makeStore() throws -> any KeyValueStore {
            switch self {
            case .inMemory: InMemoryKeyValueStore()
            case .userDefaults: try #require(UserDefaults(suiteName: Self.suiteName))
            }
        }
    }

    @Test("an absent key reads as false and 0", arguments: Backing.allCases)
    func absentKeyReadsAsDefault(_ backing: Backing) throws {
        let store = try backing.makeStore()
        let key = "absent-\(UUID().uuidString)"
        #expect(store.bool(forKey: key) == false)
        #expect(store.integer(forKey: key) == 0)
    }

    @Test("a value reads back until it is replaced or removed", arguments: Backing.allCases)
    func valueRoundTrips(_ backing: Backing) throws {
        let store = try backing.makeStore()
        let flagKey = "flag-\(UUID().uuidString)"
        let countKey = "count-\(UUID().uuidString)"
        defer {
            store.removeObject(forKey: flagKey)
            store.removeObject(forKey: countKey)
        }

        store.set(true, forKey: flagKey)
        store.set(14, forKey: countKey)
        #expect(store.bool(forKey: flagKey))
        #expect(store.integer(forKey: countKey) == 14)

        store.set(false, forKey: flagKey)
        store.set(30, forKey: countKey)
        #expect(store.bool(forKey: flagKey) == false)
        #expect(store.integer(forKey: countKey) == 30)

        store.set(true, forKey: flagKey)
        store.removeObject(forKey: flagKey)
        store.removeObject(forKey: countKey)
        #expect(store.bool(forKey: flagKey) == false)
        #expect(store.integer(forKey: countKey) == 0)
    }
}
