import CoreGraphics
import Foundation
import SwiftUI
@testable import SwiftUMLStudio
import Testing
import UniformTypeIdentifiers

@Suite("DiagramExporter.sourceExtension")
struct DiagramExporterSourceExtensionTests {

    @Test("plantuml maps to puml")
    func plantuml() {
        #expect(DiagramExporter.sourceExtension(for: "plantuml") == "puml")
    }

    @Test("mermaid maps to mmd")
    func mermaid() {
        #expect(DiagramExporter.sourceExtension(for: "mermaid") == "mmd")
    }

    @Test("nomnoml maps to nomnoml")
    func nomnoml() {
        #expect(DiagramExporter.sourceExtension(for: "nomnoml") == "nomnoml")
    }

    @Test("svg maps to svg")
    func svg() {
        #expect(DiagramExporter.sourceExtension(for: "svg") == "svg")
    }

    @Test("unknown formats fall back to txt")
    func unknownFallback() {
        #expect(DiagramExporter.sourceExtension(for: "weird-format") == "txt")
    }
}
