import Foundation
@testable import SwiftUMLBridgeFramework

/// A package written to a temporary directory. Its description lists the targets, and each
/// target's sources, in the order given, or in the reverse order. A target lives at
/// `Sources/<name>` unless `paths` gives it another directory.
struct TemporaryPackage {
    typealias Target = (name: String, files: [(name: String, source: String)])

    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("package-order-\(UUID().uuidString)", isDirectory: true)
    let targets: [Target]
    let paths: [String: String]

    init(_ targets: [Target], paths: [String: String] = [:]) throws {
        self.targets = targets
        self.paths = paths
        for target in targets {
            let directory = root.appendingPathComponent(path(of: target), isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for file in target.files {
                try file.source.write(
                    to: directory.appendingPathComponent(file.name), atomically: true, encoding: .utf8
                )
            }
        }
    }

    func description(reversed: Bool = false) -> SPMPackageDescription {
        let listed = targets.map { target in
            SPMTargetDescription(
                name: target.name, kind: .library, path: path(of: target),
                sources: reversed ? target.files.map(\.name).reversed() : target.files.map(\.name),
                dependencies: []
            )
        }
        return SPMPackageDescription(name: "Demo", targets: reversed ? listed.reversed() : listed)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private func path(of target: Target) -> String {
        paths[target.name] ?? "Sources/\(target.name)"
    }
}
