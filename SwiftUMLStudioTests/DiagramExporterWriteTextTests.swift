import CoreGraphics
import Foundation
import SwiftUI
@testable import SwiftUMLStudio
import Testing
import UniformTypeIdentifiers

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
