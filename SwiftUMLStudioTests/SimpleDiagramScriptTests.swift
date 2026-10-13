//
//  SimpleDiagramScriptTests.swift
//  SwiftUMLStudioTests
//
//  A diagram reopened from history is a SimpleDiagramScript. Its PlantUML preview loads
//  planttext.com/api/plantuml/svg/<encodeText()>, so it has to encode the way the script it was
//  saved from does.
//

import Foundation
import Testing
@testable import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio

@Suite("SimpleDiagramScript") @MainActor
struct SimpleDiagramScriptTests {

    @Test("a PlantUML diagram reopened from history encodes like the script it was saved from")
    func restoredPlantUMLEncodesLikeTheSavedScript() throws {
        let persistence = PersistenceController(inMemory: true)
        let viewModel = DiagramViewModel(persistenceController: persistence)
        viewModel.diagramMode = .dependencyGraph
        viewModel.diagramFormat = .plantuml
        var config = Configuration.default
        config.format = .plantuml
        let model = DependencyGraphModel(edges: [DependencyEdge(from: "Café", to: "Naïve", kind: .conforms)])
        let saved = DepsScript(model: model, configuration: config)
        viewModel.depsScript = saved
        viewModel.saveToHistory()

        let restored = DiagramViewModel(persistenceController: persistence)
        restored.loadHistory()
        restored.loadDiagram(try #require(restored.history.first))
        let script = try #require(restored.currentScript)

        // History percent-encoded the raw text here, which planttext.com cannot decode: it drew
        // its "Welcome to PlantUML!" placeholder instead of the diagram.
        #expect(script is SimpleDiagramScript)
        #expect(script.text == saved.text)
        #expect(script.encodeText() == saved.encodeText())
    }
}
