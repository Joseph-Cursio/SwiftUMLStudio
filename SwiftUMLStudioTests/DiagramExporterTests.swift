import CoreGraphics
import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import SwiftUMLStudio

@Suite("DiagramExportKind")
struct DiagramExportKindTests {

    @Test("PDF kind reports the pdf extension and UTType")
    func pdfMapping() {
        #expect(DiagramExportKind.pdf.fileExtension == "pdf")
        #expect(DiagramExportKind.pdf.contentType == .pdf)
    }

    @Test("PNG kind reports the png extension and UTType")
    func pngMapping() {
        #expect(DiagramExportKind.png.fileExtension == "png")
        #expect(DiagramExportKind.png.contentType == .png)
    }

    @Test("SVG kind reports the svg extension and SVG UTType")
    func svgMapping() {
        #expect(DiagramExportKind.svg.fileExtension == "svg")
        let identifier = DiagramExportKind.svg.contentType.identifier
        #expect(identifier == "public.svg-image" || identifier == "public.data")
    }

    @Test("source kind defaults to plain text")
    func sourceMapping() {
        #expect(DiagramExportKind.source.fileExtension == "txt")
        #expect(DiagramExportKind.source.contentType == .plainText)
    }
}

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

@Suite("DiagramExporter.writeText")
struct DiagramExporterWriteTextTests {

    @Test("writes UTF-8 contents that round-trip back through Data.read")
    func writesAndReadsBack() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("foo.svg")
        let payload = "<svg width=\"10\"><rect/></svg>"
        try DiagramExporter.writeText(payload, to: url)

        let readBack = try String(contentsOf: url, encoding: .utf8)
        #expect(readBack == payload)
    }
}

@Suite("DiagramExporter.renderPNG and renderPDF")
@MainActor
struct DiagramExporterRenderTests {

    @Test("renderPNG produces non-empty PNG data with a valid signature")
    func renderPNGSignature() throws {
        let view = Rectangle().fill(.blue)
        let data = try #require(
            DiagramExporter.renderPNG(view, size: CGSize(width: 32, height: 32))
        )
        #expect(data.isEmpty == false)
        // PNG magic number: 89 50 4E 47 0D 0A 1A 0A
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let prefix = Array(data.prefix(8))
        #expect(prefix == signature)
    }

    @Test("renderPDF produces non-empty PDF data with the %PDF- header")
    func renderPDFHeader() throws {
        let view = Rectangle().fill(.red)
        let data = try #require(
            DiagramExporter.renderPDF(view, size: CGSize(width: 32, height: 32))
        )
        #expect(data.isEmpty == false)
        let prefix = String(data: data.prefix(5), encoding: .ascii)
        #expect(prefix == "%PDF-")
    }
}
