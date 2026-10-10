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
    private func itemTitles(_ viewModel: DiagramViewModel) throws -> [String] {
        let menu = try DiagramExportMenu(viewModel: viewModel, viewport: DiagramViewport())
            .inspect().find(ViewType.Menu.self)
        return menu.findAll(ViewType.Button.self).compactMap { try? $0.labelView().text().string() }
    }

    @Test("no script offers no export items")
    func noScript() throws {
        #expect(try itemTitles(makeViewModel()).isEmpty)
    }

    @Test("native SVG canvas offers PDF, PNG and SVG but not source")
    func nativeCanvas() throws {
        let viewModel = makeViewModel()
        viewModel.diagramMode = .dependencyGraph
        viewModel.depsScript = depsScript(format: .svg)
        #expect(try itemTitles(viewModel) == ["Export as PDF…", "Export as PNG…", "Export SVG…"])
    }

    @Test("SVG without a native layout offers only SVG")
    func svgWithoutLayout() throws {
        let viewModel = makeViewModel()
        viewModel.restoredScript = SimpleDiagramScript(text: "<svg/>", format: .svg)
        #expect(try itemTitles(viewModel) == ["Export SVG…"])
    }

    @Test(
        "text formats offer source export with the format's extension",
        arguments: [
            (DiagramFormat.plantuml, "puml"),
            (.mermaid, "mmd"),
            (.nomnoml, "nomnoml")
        ]
    )
    func sourceExport(format: DiagramFormat, ext: String) throws {
        let viewModel = makeViewModel()
        viewModel.diagramMode = .dependencyGraph
        viewModel.depsScript = depsScript(format: format)
        #expect(try itemTitles(viewModel) == ["Export source (.\(ext))…"])
    }

    @Test("empty source text offers no export items")
    func emptySource() throws {
        let viewModel = makeViewModel()
        viewModel.restoredScript = SimpleDiagramScript(text: "", format: .plantuml)
        #expect(try itemTitles(viewModel).isEmpty)
    }

    @Test("menu is labelled with the share icon and identifiable for UI tests")
    func labelAndIdentifier() throws {
        let view = try DiagramExportMenu(viewModel: makeViewModel(), viewport: DiagramViewport()).inspect()
        let menu = try view.find(viewWithAccessibilityIdentifier: "diagramExportMenu").menu()
        let label = try menu.labelView().label()
        #expect(try label.title().text().string() == "Export")
        #expect(try label.icon().image().actualImage().name() == "square.and.arrow.up")
    }
}
