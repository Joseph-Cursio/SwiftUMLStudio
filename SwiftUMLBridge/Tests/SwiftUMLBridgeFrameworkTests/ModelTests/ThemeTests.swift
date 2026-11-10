import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

@Suite("Theme")
struct ThemeTests {

    @Test("directive theme uses given string as rawValue")
    func directiveThemeRawValue() {
        let theme = Theme.directive("my-custom-theme")
        #expect(theme.rawValue == "my-custom-theme")
    }

    @Test("single-word theme rawValue is lowercased")
    func singleWordThemeRawValue() {
        #expect(Theme.amiga.rawValue == "amiga")
        #expect(Theme.plain.rawValue == "plain")
        #expect(Theme.metal.rawValue == "metal")
        #expect(Theme.silver.rawValue == "silver")
        #expect(Theme.hacker.rawValue == "hacker")
    }

    @Test("camelCase theme rawValue converts to kebab-case")
    func camelCaseThemeRawValue() {
        #expect(Theme.carbonGray.rawValue == "carbon-gray")
        #expect(Theme.lightgray.rawValue == "lightgray")
        #expect(Theme.sketchyOutline.rawValue == "sketchy-outline")
        #expect(Theme.cloudscapeDesign.rawValue == "cloudscape-design")
    }

    @Test("reddress themes convert to kebab-case")
    func reddressThemeRawValues() {
        #expect(Theme.reddressDarkblue.rawValue == "reddress-darkblue")
        #expect(Theme.reddressDarkgreen.rawValue == "reddress-darkgreen")
        #expect(Theme.reddressDarkorange.rawValue == "reddress-darkorange")
        #expect(Theme.reddressDarkred.rawValue == "reddress-darkred")
        #expect(Theme.reddressLightblue.rawValue == "reddress-lightblue")
        #expect(Theme.reddressLightgreen.rawValue == "reddress-lightgreen")
        #expect(Theme.reddressLightorange.rawValue == "reddress-lightorange")
        #expect(Theme.reddressLightred.rawValue == "reddress-lightred")
    }

    @Test("multi-word themes produce correct kebab-case")
    func multiWordThemeRawValues() {
        #expect(Theme.awsOrange.rawValue == "aws-orange")
        #expect(Theme.blackKnight.rawValue == "black-knight")
        #expect(Theme.ceruleanOutline.rawValue == "cerulean-outline")
        #expect(Theme.cyborgOutline.rawValue == "cyborg-outline")
        #expect(Theme.materiaOutline.rawValue == "materia-outline")
        #expect(Theme.spacelabWhite.rawValue == "spacelab-white")
        #expect(Theme.superheroOutline.rawValue == "superhero-outline")
        #expect(Theme.superhero.rawValue == "superhero")
    }

    /// Each has more UTF-16 units than `Character`s, with a camel-case
    /// boundary in the units a `Character`-count range left out.
    @Test("camelCaseToKebapCase reaches a boundary after wide characters",
          arguments: [
            ("😀😀aB", "😀😀a-b"),
            ("é😀xY", "é😀x-y"),
            ("\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}fooBar",
             "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}foo-bar"),
            ("😀😀ABc", "😀😀a-bc")
          ])
    func kebabCaseAfterWideCharacters(input: String, expected: String) {
        #expect(input.camelCaseToKebapCase() == expected)
    }

    // MARK: - A config file's value

    @Test("a config value naming a built-in theme writes PlantUML's kebab-case name",
          arguments: [
            ("carbonGray", "carbon-gray"), ("sketchyOutline", "sketchy-outline"),
            ("reddressDarkblue", "reddress-darkblue"), ("minty", "minty"), ("awsOrange", "aws-orange")
          ])
    func configValueNamingBuiltIn(value: String, written: String) {
        #expect(Theme(configValue: value).rawValue == written)
    }

    /// Only a case name as written is one: anything else may be a theme the tool does not list.
    @Test("any other config value is written as it is",
          arguments: [
            "hacker from https://example.com/themes", "reddress-darkblue", "carbon-gray",
            "CarbonGray", "myTheme", "directive"
          ])
    func otherConfigValueWrittenAsIs(value: String) {
        #expect(Theme(configValue: value).rawValue == value)
    }

    @Test("a config file's camelCase theme reaches the decoded configuration in kebab-case")
    func configFileTheme() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("theme-\(UUID().uuidString).yml")
        try "theme: carbonGray\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let config = try ConfigurationProvider().loadConfiguration(at: url)
        #expect(config.theme?.rawValue == "carbon-gray")
    }

    /// `builtIn` is kept by hand beside the cases, and a case left out of it would be written as
    /// typed. Each must come back from its own name, once, and the count pins the 41 cases
    /// declared today, so a case added to `Theme` is added here and to the list together.
    @Test("every built-in theme comes back from its own case name, once")
    func builtInListsEachCaseOnce() {
        let names = Theme.builtIn.map { String(describing: $0) }
        #expect(Set(names).count == names.count)
        #expect(names.count == 41)
        for theme in Theme.builtIn {
            #expect(Theme(configValue: String(describing: theme)).rawValue == theme.rawValue)
        }
        let preferred = Theme.preferred.map(\.rawValue)
        #expect(preferred.allSatisfy { written in Theme.builtIn.contains { $0.rawValue == written } })
    }

    @Test("preferred list is non-empty and contains known themes")
    func preferredListNonEmpty() {
        #expect(Theme.preferred.isEmpty == false)
        let rawValues = Theme.preferred.map { $0.rawValue }
        #expect(rawValues.contains("amiga"))
        #expect(rawValues.contains("carbon-gray"))
    }
}
