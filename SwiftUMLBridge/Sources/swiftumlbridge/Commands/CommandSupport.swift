import ArgumentParser
import Foundation
import SwiftUMLBridgeFramework

/// The `--format` / `--output` / `--config` triplet shared by every diagram
/// subcommand. Flattened into each command via `@OptionGroup`, so the
/// command-line surface is unchanged.
struct CommonDiagramOptions: ParsableArguments {
    @Option(help: "Diagram format.")
    var format: DiagramFormat?

    @Option(help: ArgumentHelp(
        "Output format. Options: \(ClassDiagramOutput.allCases.map(\.rawValue).joined(separator: ", "))",
        valueName: "output"
    ))
    var output: ClassDiagramOutput?

    @Option(help: "Path to custom configuration file")
    var config: String?

    /// Loads the configuration file (if any) and applies the `--format` override.
    func resolvedConfiguration() -> Configuration {
        var bridgeConfig = ConfigurationProvider().getConfiguration(for: config)
        if let format {
            bridgeConfig.format = format
        }
        return bridgeConfig
    }
}

extension String {
    /// Parse a `Type.method` entry-point argument into its two halves,
    /// throwing `CLIError.invalidEntry` when it is not exactly one dotted pair.
    func parsedEntryPoint() throws -> (type: String, method: String) {
        let parts = split(separator: ".").map(String.init)
        guard parts.count == 2 else { throw CLIError.invalidEntry }
        return (parts[0], parts[1])
    }
}

extension String {
    /// The package directory a `--package` path names, read against the current directory with
    /// each `..` removed by text, as `cd` reads it (#141). `describe(at:)` and the generators are
    /// both handed this one URL, so a `..` after a symlink cannot send the manifest and the source
    /// files to different directories. Throws `CLIError.packageDirectoryNotFound`, naming the
    /// path as typed, when no directory is there.
    func packageRootURL() throws -> URL {
        let root = URL(fileURLWithPath: self).absoluteURL.standardized
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue
        else { throw CLIError.packageDirectoryNotFound(path: self) }
        return root
    }
}

extension Optional where Wrapped == ClassDiagramOutput {
    /// The presenter selected by this output option (defaults to the browser).
    var presenter: any DiagramPresenting {
        switch self {
        case .browserImageOnly: return BrowserPresenter(format: .png)
        case .consoleOnly:      return ConsolePresenter()
        default:                return BrowserPresenter(format: .default)
        }
    }

    /// The routed presenter, wrapped to warn when the SVG layout fell back to its grid.
    var reportingPresenter: any DiagramPresenting {
        LayoutFallbackReporter(inner: presenter)
    }

    /// Present `script` using the presenter selected by this output option.
    func present(_ script: any DiagramOutputting) async {
        await reportingPresenter.present(script: script)
    }
}

/// Presents through `inner`, then says on stderr when the SVG layout put the boxes on its grid
/// instead of laying them out (#150). The diagram is still written and the exit status is the
/// same: only the boxes are not where the layout would put them, and nothing else said so.
struct LayoutFallbackReporter: DiagramPresenting {
    let inner: any DiagramPresenting
    /// Where the warning goes: stderr, or a test's buffer.
    var report: @Sendable (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }

    func present(script: any DiagramOutputting) async {
        await inner.present(script: script)
        if let warning = Self.warning(for: script) {
            report(warning)
        }
    }

    /// The line to print for `script`, or `nil` when its layout did not fall back.
    static func warning(for script: any DiagramOutputting) -> String? {
        guard let reason = script.layoutGraph?.fallbackReason else { return nil }
        return "warning: the SVG layout failed (\(reason)), so the boxes are on a grid\n"
    }
}
