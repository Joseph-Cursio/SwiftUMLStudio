import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// What the user picked from the Export menu. The CLI / textual formats
/// (PlantUML, Mermaid, Nomnoml) are surfaced as `.source` and write the
/// underlying script text with a format-appropriate extension.
nonisolated enum DiagramExportKind: String, CaseIterable, Sendable {
    case pdf
    case png
    case svg
    case source

    /// File extension (without the leading dot) for this kind. For `.source`,
    /// the caller must resolve the script's format to pick `.puml`, `.mmd`,
    /// `.nomnoml`, etc.
    var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .png: return "png"
        case .svg: return "svg"
        case .source: return "txt"
        }
    }

    /// Standard UTType for `NSSavePanel`'s `allowedContentTypes`.
    var contentType: UTType {
        switch self {
        case .pdf: return .pdf
        case .png: return .png
        case .svg: return UTType("public.svg-image") ?? .data
        case .source: return .plainText
        }
    }
}

/// Pure utilities for rendering and writing diagram exports.
enum DiagramExporter {

    /// Map a script format to its conventional file extension when exported as
    /// raw source.
    nonisolated static func sourceExtension(for formatRawValue: String) -> String {
        switch formatRawValue {
        case "plantuml": return "puml"
        case "mermaid": return "mmd"
        case "nomnoml": return "nomnoml"
        case "svg": return "svg"
        default: return "txt"
        }
    }

    /// Write a UTF-8 text payload (SVG, PlantUML, Mermaid, …) to disk.
    nonisolated static func writeText(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Render a SwiftUI view to a PNG using `ImageRenderer` and return the
    /// encoded data. `scale` defaults to 2 so retina output is sharp.
    @MainActor
    static func renderPNG<V: View>(_ view: V, size: CGSize, scale: CGFloat = 2.0) -> Data? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = scale
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// Render a SwiftUI view into single-page PDF data via a `CGContext`
    /// PDF consumer. Vector — no rasterization.
    @MainActor
    static func renderPDF<V: View>(_ view: V, size: CGSize) -> Data? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        let pageBounds = CGRect(origin: .zero, size: size)
        var mediaBox = pageBounds
        let mutableData = NSMutableData()
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return nil }

        renderer.render { _, draw in
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
        }
        context.closePDF()
        return mutableData as Data
    }

    /// Configure and run an `NSSavePanel` for the given export kind. Returns
    /// the chosen URL (with the extension already enforced) or `nil` if the
    /// user cancelled.
    @MainActor
    static func runSavePanel(kind: DiagramExportKind, suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [kind.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "\(suggestedName).\(kind.fileExtension)"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
