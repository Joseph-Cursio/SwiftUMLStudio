import ArgumentParser
import Foundation
import SwiftUMLBridgeFramework

extension String {
    /// Parse a `Type.method` entry-point argument into its two halves,
    /// throwing `CLIError.invalidEntry` when it is not exactly one dotted pair.
    func parsedEntryPoint() throws -> (type: String, method: String) {
        let parts = split(separator: ".").map(Self.init)
        guard parts.count == 2 else { throw CLIError.invalidEntry }
        return (parts[0], parts[1])
    }
}
