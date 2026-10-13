import Foundation

/// The slice of `UserDefaults` the app's preference stores read and write.
///
/// The app passes `UserDefaults.standard`. The unit tests run inside the app, so they cannot
/// use `.standard` — that is the developer's own defaults — and a throwaway
/// `UserDefaults(suiteName:)` is no better: cfprefsd leaves an empty `<suite>.plist` in
/// `~/Library/Preferences` even after `removePersistentDomain(forName:)`, one per test per run.
/// Depending on this protocol lets the tests use an in-memory store instead.
nonisolated protocol KeyValueStore: AnyObject {
    func bool(forKey defaultName: String) -> Bool
    func integer(forKey defaultName: String) -> Int
    func set(_ value: Bool, forKey defaultName: String)
    func set(_ value: Int, forKey defaultName: String)
    func removeObject(forKey defaultName: String)
}

nonisolated extension UserDefaults: KeyValueStore {}
