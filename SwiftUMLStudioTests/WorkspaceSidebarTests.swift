import Foundation
import SwiftUI
import Testing
import ViewInspector
@testable import SwiftUMLStudio

@Suite("WorkspaceSidebar")
@MainActor
struct WorkspaceSidebarTests {

    private func makeView() -> WorkspaceSidebar {
        WorkspaceSidebar(viewModel: DiagramViewModel(persistenceController: .init(inMemory: true)))
    }

    @Test("lists every diagram mode as a picker row")
    func listsEveryMode() throws {
        let view = try makeView().inspect()
        for mode in DiagramMode.allCases {
            _ = try view.find(viewWithAccessibilityIdentifier: "modeRow.\(mode.rawValue)")
        }
    }

    @Test("groups modes under Structural and Behavioral sections")
    func groupsModesIntoSections() throws {
        let strings = try makeView().inspect()
            .findAll(ViewType.Text.self).compactMap { try? $0.string() }
        #expect(strings.contains("Diagrams"))
        #expect(strings.contains("Structural"))
        #expect(strings.contains("Behavioral"))
    }

    @Test("each mode row carries its SF Symbol")
    func modeRowSymbols() throws {
        let names = try makeView().inspect()
            .findAll(ViewType.Image.self).compactMap { try? $0.actualImage().name() }
        let expected = [
            "square.stack.3d.up", "point.3.connected.trianglepath.dotted", "tablecells",
            "shippingbox", "arrow.triangle.branch", "flowchart", "circle.hexagonpath"
        ]
        for symbol in expected {
            #expect(names.contains(symbol))
        }
    }

    @Test("tab picker offers Files and History")
    func tabPickerOptions() throws {
        let picker = try makeView().inspect()
            .find(viewWithAccessibilityIdentifier: "sidebarTabPicker").picker()
        let labels = picker.findAll(ViewType.Text.self).compactMap { try? $0.string() }
        // The trailing "Sidebar" is the picker's own (hidden) label.
        #expect(labels == WorkspaceSidebar.Tab.allCases.map(\.rawValue) + ["Sidebar"])
    }

    @Test("Files tab is selected initially, showing the file browser")
    func filesTabIsDefault() throws {
        let view = try makeView().inspect()
        _ = try view.find(viewWithAccessibilityIdentifier: "fileBrowser")
        #expect(throws: InspectionError.self) {
            try view.find(HistorySidebar.self)
        }
    }

    @Test("Tab identifiers match their display names")
    func tabIdentifiers() {
        for tab in WorkspaceSidebar.Tab.allCases {
            #expect(tab.id == tab.rawValue)
        }
    }
}
