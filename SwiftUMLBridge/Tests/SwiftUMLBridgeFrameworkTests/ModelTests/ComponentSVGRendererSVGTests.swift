import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

@Suite("ComponentSVGRenderer SVG output")
struct ComponentSVGRendererSVGTests {

    @Test("SVG contains an svg root, rectangles per component, and a dashed dependency line")
    func basicShape() {
        let model = ComponentModel(
            components: [
                Component(name: "Networking", kind: .library, providedInterfaces: ["HttpClient"]),
                Component(name: "App", kind: .executable),
            ],
            dependencies: [ComponentDependency(from: "App", to: "Networking")]
        )
        let svg = ComponentSVGRenderer.render(model).svg
        #expect(svg.contains("<svg"))
        #expect(svg.contains("</svg>"))
        #expect(svg.contains("«library»"))
        #expect(svg.contains("«executable»"))
        #expect(svg.contains("Networking"))
        #expect(svg.contains("HttpClient"))
        // Dependency edge — dashed line with arrow marker.
        #expect(svg.contains("stroke-dasharray"))
        #expect(svg.contains("marker-end=\"url(#arrow)\""))
    }

    @Test("special characters in names are XML-escaped")
    func escapesSpecialCharacters() {
        let model = ComponentModel(
            components: [
                Component(
                    name: "A<B>C", kind: .library,
                    providedInterfaces: ["Foo&Bar"]
                ),
            ]
        )
        let svg = ComponentSVGRenderer.render(model).svg
        #expect(svg.contains("A&lt;B&gt;C"))
        #expect(svg.contains("Foo&amp;Bar"))
        #expect(svg.contains("A<B>C") == false)
    }
}
