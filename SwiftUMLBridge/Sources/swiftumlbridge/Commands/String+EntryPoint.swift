import SwiftUMLBridgeFramework

extension String {
    /// Parse a `Type.method` entry-point argument into its type and method, split at the last dot
    /// as `EntryPointName` reads it, throwing `CLIError.invalidEntry` when it is not one.
    func parsedEntryPoint() throws -> (type: String, method: String) {
        guard let name = EntryPointName(self) else { throw CLIError.invalidEntry }
        return (name.type, name.method)
    }
}
