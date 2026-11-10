import CoreGraphics
import Foundation
import SwiftUI
@testable import SwiftUMLStudio
import Testing
import UniformTypeIdentifiers

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
