import ArgumentParser
import Foundation
import SwiftUMLBridgeFramework

/// The `discussion` lines that say which `--format` values a subcommand draws as Mermaid (#165).
/// Its emitter has no syntax of its own for them and prints Mermaid text without a warning, so the
/// help is the only place that says so. These sit in `discussion` because one `--format` help
/// serves five subcommands.
enum HelpNotes {
    /// Sequence, activity and component diagrams draw Nomnoml as Mermaid.
    static let mermaidForNomnoml = "--format nomnoml prints Mermaid text."
    /// State and ER diagrams draw Nomnoml and SVG as Mermaid.
    static let mermaidForNomnomlAndSVG = "--format nomnoml and --format svg print Mermaid text."
}
