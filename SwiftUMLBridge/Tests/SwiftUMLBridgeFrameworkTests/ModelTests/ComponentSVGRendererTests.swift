import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

@Suite("ComponentSVGRenderer layout")
struct ComponentSVGRendererLayoutTests {

    @Test("empty model produces empty layout and empty SVG")
    func emptyModel() {
        let result = ComponentSVGRenderer.render(ComponentModel())
        #expect(result.layout.components.isEmpty)
        #expect(result.layout.totalWidth == 0)
        #expect(result.layout.totalHeight == 0)
        #expect(result.svg.isEmpty)
    }

    @Test("single component is centered horizontally with non-zero size")
    func singleComponent() {
        let model = ComponentModel(
            components: [Component(name: "App", kind: .executable, providedInterfaces: ["Main"])],
            dependencies: []
        )
        let layout = ComponentSVGRenderer.computeLayout(model)
        #expect(layout.components.count == 1)
        let component = layout.components[0]
        #expect(component.width > 0)
        #expect(component.height > 0)
        // Centered: |centerX − totalWidth/2| should be 0 (within tolerance).
        #expect(abs(component.centerX - layout.totalWidth / 2) < 0.5)
    }

    @Test("two-level dependency places leaf below dependent")
    func dependencyOrdering() throws {
        let model = ComponentModel(
            components: [
                Component(name: "App", kind: .executable),
                Component(name: "Networking", kind: .library)
            ],
            dependencies: [ComponentDependency(from: "App", to: "Networking")]
        )
        let layout = ComponentSVGRenderer.computeLayout(model)
        let app = try #require(layout.component(named: "App"))
        let networking = try #require(layout.component(named: "Networking"))
        // App is the dependent — placed at the top → smaller centerY.
        #expect(app.centerY < networking.centerY)
    }

    @Test("a cycle does not crash the layout (back-edge is treated as zero contribution)")
    func cycleSurvives() {
        let model = ComponentModel(
            components: [
                Component(name: "A", kind: .library),
                Component(name: "B", kind: .library)
            ],
            dependencies: [
                ComponentDependency(from: "A", to: "B"),
                ComponentDependency(from: "B", to: "A")
            ]
        )
        let layout = ComponentSVGRenderer.computeLayout(model)
        #expect(layout.components.count == 2)
        // Both have a valid (non-NaN) position.
        for component in layout.components {
            #expect(component.centerX.isFinite)
            #expect(component.centerY.isFinite)
        }
    }

    @Test("box width scales with the longest label (header or interface)")
    func boxWidthGrowsWithLongestLabel() {
        let shortInterface = ComponentModel(
            components: [Component(name: "Lib", kind: .library, providedInterfaces: ["Foo"])]
        )
        let longInterface = ComponentModel(
            components: [Component(name: "Lib", kind: .library,
                                   providedInterfaces: ["AVeryLongPublicInterfaceName"])]
        )
        let shortWidth = ComponentSVGRenderer.computeLayout(shortInterface).components[0].width
        let longWidth = ComponentSVGRenderer.computeLayout(longInterface).components[0].width
        #expect(longWidth > shortWidth)
    }

    @Test("ordering of `components` matches the input model, not the row order")
    func preservesInputOrdering() {
        let model = ComponentModel(
            components: [
                Component(name: "A", kind: .library),
                Component(name: "B", kind: .library),
                Component(name: "C", kind: .library)
            ],
            dependencies: [
                ComponentDependency(from: "A", to: "C"),
                ComponentDependency(from: "B", to: "C")
            ]
        )
        let layout = ComponentSVGRenderer.computeLayout(model)
        #expect(layout.components.map(\.name) == ["A", "B", "C"])
    }
}

@Suite("ComponentSVGRenderer SVG output")
struct ComponentSVGRendererSVGTests {

    @Test("SVG contains an svg root, rectangles per component, and a dashed dependency line")
    func basicShape() {
        let model = ComponentModel(
            components: [
                Component(name: "Networking", kind: .library, providedInterfaces: ["HttpClient"]),
                Component(name: "App", kind: .executable)
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
            components: [Component(name: "A<B>C", kind: .library,
                                   providedInterfaces: ["Foo&Bar"])]
        )
        let svg = ComponentSVGRenderer.render(model).svg
        #expect(svg.contains("A&lt;B&gt;C"))
        #expect(svg.contains("Foo&amp;Bar"))
        #expect(!svg.contains("A<B>C"))
    }
}

@Suite("ComponentScript SVG plumbing")
struct ComponentScriptSVGTests {

    @Test("svg configuration populates componentLayout and emits SVG text")
    func svgFormatPopulatesLayout() {
        let model = ComponentModel(
            components: [Component(name: "Lib", kind: .library)]
        )
        var configuration = Configuration.default
        configuration.format = .svg
        let script = ComponentScript(model: model, configuration: configuration)
        #expect(script.format == .svg)
        #expect(script.text.contains("<svg"))
        #expect(script.componentLayout != nil)
        #expect(script.componentLayout?.components.count == 1)
    }

    @Test("plantuml configuration leaves componentLayout nil")
    func plantUMLFormatLeavesLayoutNil() {
        let model = ComponentModel(
            components: [Component(name: "Lib", kind: .library)]
        )
        let script = ComponentScript(model: model, configuration: .default)
        #expect(script.format == .plantuml)
        #expect(script.componentLayout == nil)
    }

    @Test("nomnoml configuration falls back to plantuml and leaves componentLayout nil")
    func nomnomlFallsBackToPlantUML() {
        let model = ComponentModel(
            components: [Component(name: "Lib", kind: .library)]
        )
        var configuration = Configuration.default
        configuration.format = .nomnoml
        let script = ComponentScript(model: model, configuration: configuration)
        // Nomnoml has no component-diagram dialect — fall back to PlantUML.
        #expect(script.format == .plantuml)
        #expect(script.componentLayout == nil)
    }
}
