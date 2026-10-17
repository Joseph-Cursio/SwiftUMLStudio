import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// The `elements` defaults as the code has them, which is what `docs/user/reference.md`
/// should state: `fileprivate` left out, access symbols on, `<&bolt>` on merged members.
@Suite("Element option defaults")
struct ElementOptionDefaultsTests {

    private static let everyLevelButFileprivate: [AccessLevel] = [.open, .public, .package, .internal, .private]

    private func expectDefaults(_ options: ElementOptions, _ comment: Comment) {
        #expect(options.havingAccessLevel == Self.everyLevelButFileprivate, comment)
        #expect(options.showMembersWithAccessLevel == Self.everyLevelButFileprivate, comment)
        #expect(options.showMemberAccessLevelAttribute, comment)
        #expect(options.mergedExtensionMemberIndicator == "<&bolt>", comment)
        #expect(options.showNestedTypes, comment)
        #expect(options.showGenerics, comment)
        #expect(options.showExtensions == nil, comment)
        #expect(options.exclude == nil, comment)
    }

    private func decoded(_ yaml: String) throws -> Configuration {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("element-defaults-\(UUID().uuidString).yml")
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return try #require(ConfigurationProvider().decodeYml(config: url))
    }

    @Test("ElementOptions() and Configuration.default have the defaults")
    func builtIn() {
        expectDefaults(ElementOptions(), "ElementOptions()")
        expectDefaults(Configuration.default.elements, "Configuration.default")
    }

    @Test("a config file that leaves the keys out gets the same values")
    func decodedWithoutTheKeys() throws {
        expectDefaults(try decoded("elements:\n  showGenerics: true\n").elements, "decoded")
    }

    @Test("mergedExtensionMemberIndicator: null keeps <&bolt>; an empty string drops it")
    func indicatorCannotBeNulled() throws {
        let nulled = try decoded("elements:\n  mergedExtensionMemberIndicator: null\n")
        #expect(nulled.elements.mergedExtensionMemberIndicator == "<&bolt>")
        let empty = try decoded("elements:\n  mergedExtensionMemberIndicator: \"\"\n")
        #expect(empty.elements.mergedExtensionMemberIndicator == "")
    }

    @Test("members are marked +, ~ and -, in every format")
    func accessSymbols() {
        let source = """
            public struct Box {
                public var shown = 0
                package var pkg = 0
                var plain = 0
                private var secret = 0
            }
            """
        func script(_ format: DiagramFormat) -> DiagramScript {
            ClassDiagramGenerator().generateScript(for: source, with: Configuration(format: format))
        }
        #expect(script(.plantuml).text.contains("  +shown\n  ~pkg\n  ~plain\n  -secret"))
        #expect(script(.mermaid).text.contains("    +shown\n    ~pkg\n    ~plain\n    -secret"))
        #expect(script(.nomnoml).text.contains("Box|+shown;~pkg;~plain;-secret]"))
        let items = script(.svg).layoutGraph?.nodes.flatMap { $0.compartments.flatMap(\.items) }
        #expect(items == ["+ shown", "~ pkg", "~ plain", "- secret"])
    }
}
