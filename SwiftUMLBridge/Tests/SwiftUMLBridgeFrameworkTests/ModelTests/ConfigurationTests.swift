import Testing
@testable import SwiftUMLBridgeFramework

@Suite("Configuration")
struct ConfigurationTests {

    @Test("default configuration has expected access levels")
    func defaultAccessLevels() {
        let config = Configuration.default
        #expect(config.elements.havingAccessLevel.contains(.public))
        #expect(config.elements.havingAccessLevel.contains(.internal))
        #expect(config.elements.havingAccessLevel.contains(.private))
    }

    @Test("default configuration has hide empty members command")
    func defaultHideShowCommands() {
        let config = Configuration.default
        #expect(config.hideShowCommands?.contains("hide empty members") == true)
    }

    @Test("default configuration has shadowing disabled")
    func defaultSkinparamCommands() {
        let config = Configuration.default
        #expect(config.skinparamCommands?.contains("skinparam shadowing false") == true)
    }

    @Test("default FileOptions has empty include and exclude")
    func defaultFileOptions() {
        let opts = FileOptions()
        #expect(opts.include?.isEmpty == true)
        #expect(opts.exclude?.isEmpty == true)
    }

    @Test("default ElementOptions shows generics")
    func defaultElementOptionsShowsGenerics() {
        let opts = ElementOptions()
        #expect(opts.showGenerics == true)
    }

    @Test("default ElementOptions shows nested types")
    func defaultElementOptionsShowsNestedTypes() {
        let opts = ElementOptions()
        #expect(opts.showNestedTypes == true)
    }

    @Test("Configuration.default has no theme set")
    func defaultNoTheme() {
        let config = Configuration.default
        #expect(config.theme == nil)
    }

    @Test("Version current value is non-empty")
    func versionNonEmpty() {
        #expect(Version.current.value.isEmpty == false)
    }

    // MARK: - ExtensionVisualization.from

    @Test("ExtensionVisualization.from(true) returns .all")
    func extensionVisualizationFromTrue() {
        #expect(ExtensionVisualization.from(true) == .all)
    }

    @Test("ExtensionVisualization.from(false) returns .none")
    func extensionVisualizationFromFalse() {
        #expect(ExtensionVisualization.from(false) == .none)
    }
}
