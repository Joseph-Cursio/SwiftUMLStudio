import Foundation
import SwiftUI
import Testing
import ViewInspector
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio

@Suite("ActivityControlsView — body")
@MainActor
struct ActivityControlsViewTests {

    private func makeViewModel(
        entryPoint: String = "",
        availableEntryPoints: [String] = []
    ) -> DiagramViewModel {
        let viewModel = DiagramViewModel(
            persistenceController: PersistenceController(inMemory: true)
        )
        viewModel.entryPoint = entryPoint
        viewModel.availableEntryPoints = availableEntryPoints
        return viewModel
    }

    @Test("entry-point TextField placeholder is Type.method")
    func textFieldPlaceholder() throws {
        let view = ActivityControlsView(viewModel: makeViewModel())
        let textField = try view.inspect().find(ViewType.TextField.self)
        #expect(try textField.labelView().text().string() == "Type.method")
    }

    @Test("entry-point TextField carries the accessibility identifier for UI tests")
    func textFieldHasIdentifier() throws {
        let view = ActivityControlsView(viewModel: makeViewModel())
        let textField = try view.inspect().find(
            viewWithAccessibilityIdentifier: "activityEntryPointField"
        )
        #expect(try textField.accessibilityIdentifier() == "activityEntryPointField")
    }

    @Test("entry-point TextField is bound to viewModel.entryPoint")
    func textFieldBindsToEntryPoint() throws {
        let viewModel = makeViewModel(entryPoint: "Foo.run")
        let view = ActivityControlsView(viewModel: viewModel)
        let textField = try view.inspect().find(ViewType.TextField.self)
        #expect(try textField.input() == "Foo.run")
    }

    @Test("menu shows 'No entry points found' when the list is empty")
    func emptyEntryPointsMessage() throws {
        let view = ActivityControlsView(viewModel: makeViewModel(availableEntryPoints: []))
        let strings = try view.inspect().findAll(ViewType.Text.self)
            .compactMap { try? $0.string() }
        #expect(strings.contains("No entry points found"))
    }

    @Test("menu renders one button per available entry point")
    func entryPointButtonsRendered() throws {
        let view = ActivityControlsView(viewModel: makeViewModel(
            availableEntryPoints: ["Alpha.act", "Beta.run", "Gamma.go"]
        ))
        let buttons = try view.inspect().findAll(ViewType.Button.self)
        let labels = buttons.compactMap { try? $0.labelView().text().string() }
        #expect(labels.contains("Alpha.act"))
        #expect(labels.contains("Beta.run"))
        #expect(labels.contains("Gamma.go"))
    }

    @Test("tapping an entry-point button updates viewModel.entryPoint")
    func tappingButtonUpdatesEntryPoint() throws {
        let viewModel = makeViewModel(availableEntryPoints: ["Alpha.act", "Beta.run"])
        let view = ActivityControlsView(viewModel: viewModel)
        let button = try view.inspect().find(button: "Beta.run")
        try button.tap()
        #expect(viewModel.entryPoint == "Beta.run")
    }

    @Test("menu icon carries the accessibility identifier for UI tests")
    func menuHasIdentifier() throws {
        let view = ActivityControlsView(viewModel: makeViewModel())
        let menu = try view.inspect().find(
            viewWithAccessibilityIdentifier: "activityEntryPointMenu"
        )
        #expect(try menu.accessibilityIdentifier() == "activityEntryPointMenu")
    }
}
