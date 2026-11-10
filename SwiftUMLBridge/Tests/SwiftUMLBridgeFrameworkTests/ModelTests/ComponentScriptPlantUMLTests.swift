import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

@Suite("ComponentScript PlantUML emission")
struct ComponentScriptPlantUMLTests {

    @Test("emits a component block + dashed dependency arrow")
    func basicShape() {
        let model = ComponentModel(
            components: [
                Component(name: "Networking", kind: .library, providedInterfaces: ["HttpClient"]),
                Component(name: "App", kind: .executable, providedInterfaces: ["AppMain"]),
            ],
            dependencies: [ComponentDependency(from: "App", to: "Networking")]
        )
        let script = ComponentScript(model: model, configuration: .default)
        #expect(script.text.contains("@startuml"))
        #expect(script.text.contains("component \"Networking\" as Networking <<library>>"))
        #expect(script.text.contains("component \"App\" as App <<executable>>"))
        #expect(script.text.contains("[HttpClient]"))
        #expect(script.text.contains("[AppMain]"))
        #expect(script.text.contains("App ..> Networking"))
        #expect(script.text.contains("@enduml"))
    }

    @Test("safeAlias replaces special characters")
    func safeAliasReplaces() {
        let model = ComponentModel(
            components: [
                Component(name: "swift-syntax", kind: .library),
                Component(name: "App.Main", kind: .executable),
            ],
            dependencies: [ComponentDependency(from: "App.Main", to: "swift-syntax")]
        )
        let script = ComponentScript(model: model, configuration: .default)
        #expect(script.text.contains("as swift_syntax"))
        #expect(script.text.contains("as App_Main"))
        #expect(script.text.contains("App_Main ..> swift_syntax"))
    }

    @Test("empty components emit only the @startuml/@enduml frame")
    func emptyModelPlantUML() {
        let script = ComponentScript(model: ComponentModel(), configuration: .default)
        #expect(script.text.contains("@startuml"))
        #expect(script.text.contains("@enduml"))
    }
}
