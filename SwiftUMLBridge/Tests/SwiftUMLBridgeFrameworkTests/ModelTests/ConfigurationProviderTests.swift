import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

@Suite("ConfigurationProvider")
struct ConfigurationProviderTests {

    private let provider = ConfigurationProvider()

    private var projectMockURL: URL {
        Bundle.module.resourceURL!
            .appendingPathComponent("TestData")
            .appendingPathComponent("ProjectMock")
    }

    @Test("defaultYmlPath filename is .swiftumlbridge.yml")
    func defaultYmlPathFilename() {
        #expect(provider.defaultYmlPath.lastPathComponent == ".swiftumlbridge.yml")
    }

    @Test("defaultConfig returns Configuration.default")
    func defaultConfigIsConfigurationDefault() {
        let config = provider.defaultConfig
        #expect(config.hideShowCommands?.contains("hide empty members") == true)
    }

    @Test("getConfiguration with nil path invokes readSwiftConfig")
    func nilPathReadsSwiftConfig() {
        let config = provider.getConfiguration(for: nil)
        #expect(config.hideShowCommands != nil)
    }

    @Test("getConfiguration with non-existent path falls back to default")
    func nonExistentPathFallsBack() {
        let config = provider.getConfiguration(for: "/nonexistent/path/config.yml")
        #expect(config.hideShowCommands?.contains("hide empty members") == true)
    }

    @Test("getConfiguration loads valid YAML from custom path")
    func loadsValidCustomConfig() {
        let configPath = projectMockURL.appendingPathComponent("customConfigSimple.yml").path
        let config = provider.getConfiguration(for: configPath)
        #expect(config.elements.havingAccessLevel.contains(.public) == true)
        #expect(config.elements.showGenerics == false)
    }

    @Test("getConfiguration with invalid YAML falls back to defaults")
    func invalidYAMLFallsBack() {
        let corruptPath = projectMockURL.appendingPathComponent("customConfigBadDataCorrupt.yml").path
        let config = provider.getConfiguration(for: corruptPath)
        #expect(config.hideShowCommands != nil)
    }

    @Test("decodeYml returns nil for non-existent file")
    func decodeYmlNonExistentFile() {
        let url = URL(fileURLWithPath: "/this/path/does/not/exist.yml")
        let result = provider.decodeYml(config: url)
        #expect(result == nil)
    }

    @Test("decodeYml returns Configuration for valid YAML file")
    func decodeYmlValidFile() {
        let url = projectMockURL.appendingPathComponent("customConfigSimple.yml")
        let result = provider.decodeYml(config: url)
        #expect(result != nil)
    }

    @Test("decodeYml returns nil for corrupt YAML file")
    func decodeYmlCorruptFile() {
        let url = projectMockURL.appendingPathComponent("customConfigBadDataCorrupt.yml")
        let result = provider.decodeYml(config: url)
        #expect(result == nil)
    }

    @Test("readSwiftConfig returns a valid Configuration")
    func readSwiftConfigReturnsConfig() {
        let config = provider.readSwiftConfig()
        #expect(config.hideShowCommands != nil || config.skinparamCommands != nil)
    }

    @Test("simple YAML config sets relationship labels")
    func simpleYAMLSetsRelationshipLabels() {
        let url = projectMockURL.appendingPathComponent("customConfigSimple.yml")
        if let config = provider.decodeYml(config: url) {
            #expect(config.relationships.inheritance?.label == "inherits from")
        }
    }

    @Test("simple YAML config sets page texts")
    func simpleYAMLSetsPageTexts() {
        let url = projectMockURL.appendingPathComponent("customConfigSimple.yml")
        if let config = provider.decodeYml(config: url) {
            #expect(config.texts != nil)
            #expect(config.texts?.header == "headerText")
            #expect(config.texts?.title == "titleText")
            #expect(config.texts?.footer == "footerText")
        }
    }

    @Test("simple YAML config sets exclude patterns in files")
    func simpleYAMLSetsFileExclude() {
        let url = projectMockURL.appendingPathComponent("customConfigSimple.yml")
        if let config = provider.decodeYml(config: url) {
            #expect(config.files.exclude?.isEmpty == false)
        }
    }

    @Test("simple YAML config sets element exclude list")
    func simpleYAMLSetsElementExclude() {
        let url = projectMockURL.appendingPathComponent("customConfigSimple.yml")
        if let config = provider.decodeYml(config: url) {
            #expect(config.elements.exclude?.contains("UIViewController") == true)
        }
    }

    @Test("simple YAML config sets hideShowCommands")
    func simpleYAMLSetsHideShowCommands() {
        let url = projectMockURL.appendingPathComponent("customConfigSimple.yml")
        if let config = provider.decodeYml(config: url) {
            #expect(config.hideShowCommands?.isEmpty == false)
        }
    }
}
