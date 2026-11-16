import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

/// `swift package describe` leaves target settings out, so whether a target enables
/// `MemberImportVisibility` is read from `swift package dump-package`, whose settings look like
/// `{"kind": {"enableUpcomingFeature": {"_0": "MemberImportVisibility"}}, "tool": "swift"}` (#201).
/// Each manifest declares the traits of a real dump: `default` enables Base, which enables
/// Chained, and Off is on only when asked for, so `swift build` turns on Base and Chained.
@Suite("SPMPackageReader reads MemberImportVisibility from the dumped manifest")
struct SPMManifestSettingsTests {
    private static let traits = #"""
        [{"enabledTraits": ["Chained"], "name": "Base"}, {"enabledTraits": [], "name": "Chained"},
         {"enabledTraits": [], "name": "Off"}, {"enabledTraits": ["Base"], "name": "default"}]
        """#

    /// A dumped manifest whose one target, `Mod`, has `settings`, a comma-separated list.
    private static func manifest(_ settings: String) -> Data {
        Data(#"{"name": "Probe", "traits": \#(traits), "targets": [{"name": "Mod", "settings": [\#(settings)]}]}"#.utf8)
    }

    private static let upcoming = #"{"enableUpcomingFeature": {"_0": "MemberImportVisibility"}}"#
    private static let disabling = #"{"unsafeFlags": {"_0": ["-disable-upcoming-feature", "MemberImportVisibility"]}}"#

    private static func swiftSetting(_ kind: String, condition: String? = nil) -> String {
        #"{"kind": \#(kind), "tool": "swift""# + (condition.map { #", "condition": \#($0)"# } ?? "") + "}"
    }

    static let enabling: [(String, String)] = [
        ("an upcoming feature", swiftSetting(#"{"enableUpcomingFeature": {"_0": "MemberImportVisibility"}}"#)),
        ("an experimental feature", swiftSetting(#"{"enableExperimentalFeature": {"_0": "MemberImportVisibility"}}"#)),
        ("unsafe flags", swiftSetting(
            #"{"unsafeFlags": {"_0": ["-Onone", "-enable-upcoming-feature", "MemberImportVisibility"]}}"#
        )),
        ("a condition on macOS", swiftSetting(
            #"{"enableUpcomingFeature": {"_0": "MemberImportVisibility"}}"#,
            condition: #"{"platformNames": ["linux", "macos"]}"#
        )),
        ("a condition on debug builds", swiftSetting(
            #"{"enableUpcomingFeature": {"_0": "MemberImportVisibility"}}"#, condition: #"{"config": "debug"}"#
        )),
        ("a condition on a default trait", swiftSetting(upcoming, condition: #"{"traits": ["Base"]}"#)),
        ("a condition on a trait a default one enables", swiftSetting(
            upcoming, condition: #"{"traits": ["Chained"]}"#
        )),
        ("a condition on traits, one of them on", swiftSetting(upcoming, condition: #"{"traits": ["Off", "Base"]}"#)),
        ("unsafe flags through -Xfrontend", swiftSetting(
            #"""
            {"unsafeFlags": {"_0": ["-Xfrontend", "-enable-upcoming-feature",
                                    "-Xfrontend", "MemberImportVisibility"]}}
            """#
        )),
        ("a feature after a flag that disables it", swiftSetting(disabling) + ", " + swiftSetting(upcoming)),
    ]

    static let notEnabling: [(String, String)] = [
        ("another feature", swiftSetting(#"{"enableUpcomingFeature": {"_0": "ExistentialAny"}}"#)),
        ("another tool", #"{"kind": {"enableUpcomingFeature": {"_0": "MemberImportVisibility"}}, "tool": "c"}"#),
        ("a flag without its feature", swiftSetting(#"{"unsafeFlags": {"_0": ["MemberImportVisibility"]}}"#)),
        ("a condition on Linux alone", swiftSetting(
            #"{"enableUpcomingFeature": {"_0": "MemberImportVisibility"}}"#,
            condition: #"{"platformNames": ["linux"]}"#
        )),
        ("a condition on release builds", swiftSetting(
            #"{"enableUpcomingFeature": {"_0": "MemberImportVisibility"}}"#, condition: #"{"config": "release"}"#
        )),
        ("a condition on a trait that is not on by default", swiftSetting(
            upcoming, condition: #"{"traits": ["Off"]}"#
        )),
        ("a flag that disables a feature before it", swiftSetting(upcoming) + ", " + swiftSetting(disabling)),
        ("unsafe flags that enable and then disable it", swiftSetting(#"""
            {"unsafeFlags": {"_0": ["-enable-upcoming-feature", "MemberImportVisibility",
                                    "-disable-upcoming-feature", "MemberImportVisibility"]}}
            """#)),
    ]

    @Test("a setting that enables the feature", arguments: enabling)
    func enables(_ name: String, setting: String) {
        let targets = SPMPackageReader.memberImportVisibilityTargets(inManifest: Self.manifest(setting))
        #expect(targets == ["Mod"], "\(name)")
    }

    @Test("a setting that does not", arguments: notEnabling)
    func doesNotEnable(_ name: String, setting: String) {
        #expect(SPMPackageReader.memberImportVisibilityTargets(inManifest: Self.manifest(setting)).isEmpty, "\(name)")
    }

    @Test("a manifest that is not a dumped package enables nothing")
    func malformedManifest() {
        #expect(SPMPackageReader.memberImportVisibilityTargets(inManifest: Data("not json".utf8)).isEmpty)
        #expect(SPMPackageReader.memberImportVisibilityTargets(inManifest: Data(#"{"name": "P"}"#.utf8)).isEmpty)
    }

    @Test("parse marks the targets the manifest enables it for, and none without a manifest")
    func parseMarksTargets() throws {
        let described = Data(#"""
            {"name": "Probe", "targets": [
                {"name": "ModA", "path": "Sources/ModA", "type": "library", "sources": ["A.swift"]},
                {"name": "ModC", "path": "Sources/ModC", "type": "library", "sources": ["C.swift"]}
            ]}
            """#.utf8)
        let manifest = Data(#"""
            {"name": "Probe", "targets": [
                {"name": "ModA", "settings": []},
                {"name": "ModC", "settings": [
                    {"kind": {"enableUpcomingFeature": {"_0": "MemberImportVisibility"}}, "tool": "swift"}
                ]}
            ]}
            """#.utf8)
        let package = try SPMPackageReader.parse(described, manifest: manifest)
        #expect(package.targets.map(\.enablesMemberImportVisibility) == [false, true])
        #expect(try SPMPackageReader.parse(described).targets.allSatisfy { !$0.enablesMemberImportVisibility })
    }
}
