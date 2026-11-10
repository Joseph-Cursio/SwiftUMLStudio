import CoreGraphics
import Foundation
import SwiftUI
@testable import SwiftUMLStudio
import Testing
import UniformTypeIdentifiers

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
