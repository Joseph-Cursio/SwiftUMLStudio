import Foundation
import SwiftUMLBridgeFramework

/// Loads the configuration a run uses, and says when a file cannot be used (#138). A file the
/// user names with `--config` must load: the run fails with the reason, and does not fall back to
/// the current directory's file or the defaults. That `.swiftumlbridge.yml` is read only when no
/// `--config` is given; when it cannot be used, a warning on stderr says why and the run goes on
/// with the defaults, so a stray file in a directory never stops a run.
struct ConfigurationLoader {
    var provider = ConfigurationProvider()
    /// The file read when no `--config` is given.
    var discoveredFile = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".swiftumlbridge.yml")
    /// Where the warning goes: stderr, or a test's buffer.
    var warn: @Sendable (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }

    func load(_ path: String?) throws -> Configuration {
        if let path {
            BridgeLogger.shared.info("reading config file \(path)")
            do {
                return try provider.loadConfiguration(at: URL(fileURLWithPath: path))
            } catch let error as ConfigurationLoadError {
                throw CLIError.invalidConfiguration(path: path, reason: error.reason)
            }
        }
        guard FileManager.default.fileExists(atPath: discoveredFile.path) else {
            let name = discoveredFile.lastPathComponent
            BridgeLogger.shared.info("no \(name) in the current directory; using the defaults")
            return .default
        }
        BridgeLogger.shared.info("reading config file \(discoveredFile.path)")
        do {
            return try provider.loadConfiguration(at: discoveredFile)
        } catch let error as ConfigurationLoadError {
            warn("warning: ignoring \(discoveredFile.lastPathComponent): \(error.reason)\n")
            return .default
        }
    }
}
