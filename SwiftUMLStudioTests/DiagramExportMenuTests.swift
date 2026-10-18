import Foundation
import SwiftUI
import Testing
import ViewInspector
@testable import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio

@Suite("DiagramExportMenu")
@MainActor
struct DiagramExportMenuTests {

    private func makeViewModel() -> DiagramViewModel {
        DiagramViewModel(persistenceController: .init(inMemory: true))
    }

    private func depsScript(format: DiagramFormat) -> DepsScript {
        var config = Configuration.default
        config.format = format
        let model = DependencyGraphModel(edges: [DependencyEdge(from: "A", to: "B", kind: .conforms)])
        return DepsScript(model: model, configuration: config)
    }

    /// Titles of the menu's items, in order.
    private func itemTitles(_ viewModel: DiagramViewModel) async throws -> [String] {
        try await DiagramExportMenu(viewModel: viewModel, viewport: DiagramViewport()).inspectHosted { view in
            try view.find(ViewType.Menu.self)
                .findAll(ViewType.Button.self).compactMap { try? $0.labelView().text().string() }
        }
    }

    @Test("no script offers no export items")
    func noScript() async throws {
        #expect(try await itemTitles(makeViewModel()).isEmpty)
    }

    @Test("native SVG canvas offers PDF, PNG and SVG but not source")
    func nativeCanvas() async throws {
        let viewModel = makeViewModel()
        viewModel.diagramMode = .dependencyGraph
        viewModel.depsScript = depsScript(format: .svg)
        #expect(try await itemTitles(viewModel) == ["Export as PDF…", "Export as PNG…", "Export SVG…"])
    }

    @Test("SVG without a native layout offers only SVG")
    func svgWithoutLayout() async throws {
        let viewModel = makeViewModel()
        viewModel.restoredScript = SimpleDiagramScript(text: "<svg/>", format: .svg)
        #expect(try await itemTitles(viewModel) == ["Export SVG…"])
    }

    @Test(
        "text formats offer source export with the format's extension",
        arguments: [
            (DiagramFormat.plantuml, "puml"),
            (.mermaid, "mmd"),
            (.nomnoml, "nomnoml")
        ]
    )
    func sourceExport(format: DiagramFormat, ext: String) async throws {
        let viewModel = makeViewModel()
        viewModel.diagramMode = .dependencyGraph
        viewModel.depsScript = depsScript(format: format)
        #expect(try await itemTitles(viewModel) == ["Export source (.\(ext))…"])
    }

    @Test("empty source text offers no export items")
    func emptySource() async throws {
        let viewModel = makeViewModel()
        viewModel.restoredScript = SimpleDiagramScript(text: "", format: .plantuml)
        #expect(try await itemTitles(viewModel).isEmpty)
    }

    @Test("menu is labelled with the share icon and identifiable for UI tests")
    func labelAndIdentifier() async throws {
        let menu = DiagramExportMenu(viewModel: makeViewModel(), viewport: DiagramViewport())
        try await menu.inspectHosted { view in
            let label = try view.find(viewWithAccessibilityIdentifier: "diagramExportMenu").menu()
                .labelView().label()
            #expect(try label.title().text().string() == "Export")
            #expect(try label.icon().image().actualImage().name() == "square.and.arrow.up")
        }
    }
}
