@testable import SwiftUMLBridgeFramework

/// Reads ids and edges back out of class-diagram scripts, for the alias tests (#54).
///
/// Class-diagram ids come from `DiagramContext.uniqName`: Mermaid declares `class <alias>[…]`,
/// PlantUML `class "<name>" as <alias><generics>` and `note as <alias>`. Both formats also give
/// an edge's undeclared end a node of its own, so an alias must not equal one either.
enum ClassDiagramIds {

    static func script(
        for source: String,
        format: DiagramFormat,
        elements: ElementOptions = ElementOptions()
    ) -> String {
        ClassDiagramGenerator()
            .generateScript(for: source, with: Configuration(elements: elements, format: format))
            .text
    }

    /// The id of every Mermaid class declaration: `class <id>["<label>"] {`.
    static func mermaid(in script: String) -> [String] {
        script.split(separator: "\n")
            .filter { $0.hasPrefix("class ") }
            .map { String($0.dropFirst("class ".count).prefix { $0 != "[" }) }
    }

    /// Every id a PlantUML script declares: `class "<name>" as <id><generics> …` and `note as <id>`.
    static func plantUML(in script: String) -> [String] {
        script.split(separator: "\n").compactMap { line -> String? in
            if line.hasPrefix("note as ") {
                return String(line.dropFirst("note as ".count).prefix { $0 != " " })
            }
            guard line.hasPrefix("class \""), let range = line.range(of: " as ") else { return nil }
            return String(line[range.upperBound...].prefix { $0 != " " && $0 != "<" })
        }
    }

    static func mermaid(for source: String, elements: ElementOptions = ElementOptions()) -> [String] {
        mermaid(in: script(for: source, format: .mermaid, elements: elements))
    }

    static func plantUML(for source: String, elements: ElementOptions = ElementOptions()) -> [String] {
        plantUML(in: script(for: source, format: .plantuml, elements: elements))
    }

    static func lines(of script: String, containing marker: String) -> [String] {
        script.split(separator: "\n").map(String.init).filter { $0.contains(marker) }
    }
}
