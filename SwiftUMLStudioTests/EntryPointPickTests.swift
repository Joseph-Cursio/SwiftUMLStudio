import Foundation
import SwiftUI
import SwiftUMLBridgeFramework
import Testing
import ViewInspector
@testable import SwiftUMLStudio

/// The entry list offered names the Studio could not draw (#234). Picking `NS.Real.run`, from
/// `extension NS.Real`, generated nothing and set no error: the previous entry's diagram stayed up
/// under its own title, or with none, the pane asked for files already selected. A function local
/// to a body was listed too, and drew a blank activity diagram.
@Suite("Picking an entry from the list")
@MainActor
struct EntryPointPickTests {
    private static let nested = """
        enum NS { struct Real {} }
        extension NS.Real {
            func run() { helper() }
            func helper() {}
        }
        struct Other {
            func go() { step() }
            func step() {}
        }
        struct Host {
            init() {
                func setup() { work() }
                setup()
            }
            func work() {}
        }
        """

    private func file(_ source: String = nested) throws -> String {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("Real.swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    private func viewModel(mode: DiagramMode) throws -> DiagramViewModel {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.selectedPaths = [try file()]
        viewModel.diagramMode = mode
        return viewModel
    }

    private func generate(_ viewModel: DiagramViewModel, entry: String) async {
        viewModel.entryPoint = entry
        viewModel.generate()
        await viewModel.currentTask?.value
    }

    @Test("the list offers the nested type's method by its whole name, and no local function")
    func listOffersOnlyMembers() throws {
        let viewModel = try viewModel(mode: .sequenceDiagram)
        viewModel.refreshEntryPoints()
        #expect(viewModel.availableEntryPoints.contains("NS.Real.run"))
        #expect(viewModel.availableEntryPoints.contains("Host.work"))
        #expect(!viewModel.availableEntryPoints.contains("Host.setup"))
    }

    @Test("a listed nested type's method replaces the previous diagram",
          arguments: [DiagramMode.sequenceDiagram, .activityDiagram])
    func nestedEntryDraws(mode: DiagramMode) async throws {
        let viewModel = try viewModel(mode: mode)
        await generate(viewModel, entry: "Other.go")
        #expect(viewModel.currentScript?.text.contains("title Other.go") == true)

        await generate(viewModel, entry: "NS.Real.run")
        let text = try #require(viewModel.currentScript?.text)
        #expect(text.contains("title NS.Real.run"), "\(text)")
        #expect(text.contains("helper()"), "\(text)")
        #expect(viewModel.errorMessage == nil)
    }

    @Test("a name that is no Type.method clears the previous diagram and says why",
          arguments: [DiagramMode.sequenceDiagram, .activityDiagram])
    func unreadableEntryClearsAndExplains(mode: DiagramMode) async throws {
        let viewModel = try viewModel(mode: mode)
        await generate(viewModel, entry: "Other.go")
        #expect(viewModel.currentScript != nil)

        await generate(viewModel, entry: "Other.")
        #expect(viewModel.currentScript == nil)
        #expect(viewModel.isGenerating == false)
        #expect(viewModel.entryPointIsUnreadable)
        try await DiagramPreviewView(viewModel: viewModel).inspectHosted { view in
            _ = try view.find(viewWithAccessibilityIdentifier: "entryPointUnreadablePrompt")
        }
    }

    @Test("a name being typed is unreadable only in the modes that take an entry")
    func unreadableOnlyWithEntryModes() throws {
        let viewModel = try viewModel(mode: .classDiagram)
        viewModel.entryPoint = "Other"
        #expect(!viewModel.entryPointIsUnreadable)
        viewModel.diagramMode = .sequenceDiagram
        #expect(viewModel.entryPointIsUnreadable)
        viewModel.entryPoint = "Other.go"
        #expect(!viewModel.entryPointIsUnreadable)
    }

    @Test("the dashboard's cards offer no local function")
    func cardsOfferNoLocalFunction() throws {
        let summary = ProjectAnalyzer.analyze(paths: [try file()])
        #expect(!summary.entryPoints.contains("Host.setup"))
        let titles = SuggestionEngine.generate(from: summary, isProUnlocked: true).map(\.title)
        #expect(!titles.contains { $0.hasSuffix("Host.setup") })
    }
}
