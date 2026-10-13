import Foundation
@testable import SwiftUMLStudio

/// A ``KeyValueStore`` that never reaches `UserDefaults`, for tests of the app's preference stores.
///
/// The unit tests run inside the app, so `UserDefaults.standard` is the developer's own
/// defaults, and a throwaway `UserDefaults(suiteName:)` suite leaves an empty plist in
/// `~/Library/Preferences` on every run. ``KeyValueStoreTests`` checks that this store
/// answers the way `UserDefaults` does.
final class InMemoryKeyValueStore: KeyValueStore {
    private var values: [String: Any] = [:]

    func bool(forKey defaultName: String) -> Bool {
        values[defaultName] as? Bool ?? false
    }

    func integer(forKey defaultName: String) -> Int {
        values[defaultName] as? Int ?? 0
    }

    func set(_ value: Bool, forKey defaultName: String) {
        values[defaultName] = value
    }

    func set(_ value: Int, forKey defaultName: String) {
        values[defaultName] = value
    }

    func removeObject(forKey defaultName: String) {
        values[defaultName] = nil
    }
}
