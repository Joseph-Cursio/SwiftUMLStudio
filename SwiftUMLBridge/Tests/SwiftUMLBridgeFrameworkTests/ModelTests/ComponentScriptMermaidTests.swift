import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

@Suite("ComponentScript Mermaid (flowchart fallback)")
struct ComponentScriptMermaidTests {

    @Test("emits flowchart TD with subgraphs and dashed arrows")
    func mermaidFlowchartShape() {
        let model = ComponentModel(
            components: [
                Component(name: "Networking", kind: .library, providedInterfaces: ["HttpClient"]),
                Component(name: "App", kind: .executable, providedInterfaces: []),
            ],
            dependencies: [ComponentDependency(from: "App", to: "Networking")]
        )
        var configuration = Configuration.default
        configuration.format = .mermaid
        let script = ComponentScript(model: model, configuration: configuration)
        #expect(script.text.contains("flowchart TD"))
        #expect(script.text.contains("subgraph Networking[\"Networking\"]"))
        #expect(script.text.contains("App -.-> Networking"))
    }
}
