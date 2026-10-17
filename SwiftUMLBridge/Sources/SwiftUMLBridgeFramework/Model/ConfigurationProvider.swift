import Foundation
import Yams

/// Load Configuration from file or defaults
public struct ConfigurationProvider {
    public init() {}

    public func getConfiguration(for path: String?) -> Configuration {
        guard let configPath = path else {
            return readSwiftConfig()
        }
        BridgeLogger.shared.info("search config file with custom location \(configPath)")
        let fileURL = URL(fileURLWithPath: configPath)
        if let config = decodeYml(config: fileURL) {
            BridgeLogger.shared.info("config file \(configPath) found")
            return config
        } else {
            return readSwiftConfig()
        }
    }

    func readSwiftConfig() -> Configuration {
        BridgeLogger.shared.info("search for config file in current directory with name '.swiftumlbridge.yml'")
        if let config = decodeYml(config: defaultYmlPath) {
            BridgeLogger.shared.info(".swiftumlbridge.yml file found")
            return config
        } else {
            BridgeLogger.shared.info("return default configuration")
            return defaultConfig
        }
    }

    var defaultYmlPath: URL {
        let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return dir.appendingPathComponent(".swiftumlbridge.yml")
    }

    func decodeYml(config: URL) -> Configuration? {
        do {
            return try loadConfiguration(at: config)
        } catch let error as ConfigurationLoadError where error.isMissingFile {
            BridgeLogger.shared.info("cannot find/read yaml file")
        } catch {
            BridgeLogger.shared.error("\(error)")
        }
        return nil
    }

    /// The configuration in the YAML file at `url`. Unlike `getConfiguration(for:)`, which
    /// falls back to the defaults, this says why a file cannot be used, so a caller can report
    /// it (#138). A file with no settings in it, empty or only comments, is all defaults.
    ///
    /// - Throws: `ConfigurationLoadError`, naming the file, and the key and value at fault.
    public func loadConfiguration(at url: URL) throws -> Configuration {
        // Through a file handle, which reads `/dev/null` and a shell's `<(…)` as well: `String(contentsOf:)`
        // cannot read either.
        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            data = try handle.readToEnd() ?? Data()
        } catch {
            let missing = !FileManager.default.fileExists(atPath: url.path)
            throw ConfigurationLoadError(
                path: url.path, reason: missing ? "no such file" : "the file cannot be read", isMissingFile: missing
            )
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ConfigurationLoadError(path: url.path, reason: "the file is not UTF-8 text")
        }
        do {
            // `YAMLDecoder` rejects a document with nothing in it, or only `---` or `~`.
            guard let root = try Yams.compose(yaml: text), root.null == nil else { return defaultConfig }
            return try YAMLDecoder().decode(Configuration.self, from: text)
        } catch {
            throw ConfigurationLoadError(path: url.path, reason: Self.reason(for: error))
        }
    }

    /// Why `error` stopped a decode, with the path to the key at fault: `invalid value at
    /// relationships.inheritance.style.lineColor: 'Foo' is not a colour name this tool knows`.
    static func reason(for error: Error) -> String {
        guard let decodingError = error as? DecodingError else { return "\(error)" }
        switch decodingError {
        case let .keyNotFound(key, context):
            let parent = keyPath(context.codingPath)
            return "missing key '\(key.stringValue)'" + (parent.isEmpty ? "" : " in \(parent)")
        case let .dataCorrupted(context), let .typeMismatch(_, context), let .valueNotFound(_, context):
            let path = keyPath(context.codingPath)
            let detail = context.underlyingError.map { "\($0)" } ?? context.debugDescription
            return path.isEmpty ? detail : "invalid value at \(path): \(detail)"
        @unknown default:
            return "\(error)"
        }
    }

    /// `elements.havingAccessLevel[0]` for the keys down to the first entry of that list.
    private static func keyPath(_ codingPath: [CodingKey]) -> String {
        codingPath.reduce(into: "") { path, key in
            if let index = key.intValue {
                path += "[\(index)]"
            } else {
                path += (path.isEmpty ? "" : ".") + key.stringValue
            }
        }
    }

    var defaultConfig: Configuration {
        Configuration.default
    }
}

/// Why a configuration file could not be used: `ConfigurationProvider.loadConfiguration(at:)`.
public struct ConfigurationLoadError: Error, CustomStringConvertible, Sendable {
    /// The file's path.
    public let path: String
    /// What is wrong with it, naming the key and the value at fault where there is one.
    public let reason: String
    /// Whether nothing is at `path`.
    public let isMissingFile: Bool

    public init(path: String, reason: String, isMissingFile: Bool = false) {
        self.path = path
        self.reason = reason
        self.isMissingFile = isMissingFile
    }

    public var description: String { "\(path): \(reason)" }
}
