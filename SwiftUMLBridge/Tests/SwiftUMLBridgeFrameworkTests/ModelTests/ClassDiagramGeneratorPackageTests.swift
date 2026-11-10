import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

@Suite("ClassDiagramGenerator.generateScript(forPackage:)")
struct ClassDiagramGeneratorPackageTests {

    /// Build a temp directory mimicking a small SPM package, run the
    /// generator against it, and check the resulting LayoutGraph carries
    /// module info on each node.
    @Test("tags each LayoutNode with its owning target name")
    func tagsLayoutNodesWithModule() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spm-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let networkingDir = tempRoot.appendingPathComponent("Sources/Networking", isDirectory: true)
        let uiDir = tempRoot.appendingPathComponent("Sources/UI", isDirectory: true)
        try FileManager.default.createDirectory(at: networkingDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: uiDir, withIntermediateDirectories: true)
        try "class HttpClient {}".write(
            to: networkingDir.appendingPathComponent("HttpClient.swift"),
            atomically: true, encoding: .utf8
        )
        try "class LoginView {}".write(
            to: uiDir.appendingPathComponent("LoginView.swift"),
            atomically: true, encoding: .utf8
        )

        let description = SPMPackageDescription(
            name: "Demo",
            targets: [
                SPMTargetDescription(
                    name: "Networking", kind: .library,
                    path: "Sources/Networking",
                    sources: ["HttpClient.swift"], dependencies: []
                ),
                SPMTargetDescription(
                    name: "UI", kind: .library,
                    path: "Sources/UI",
                    sources: ["LoginView.swift"], dependencies: ["Networking"]
                ),
            ]
        )

        var configuration = Configuration.default
        configuration.format = .svg
        let script = ClassDiagramGenerator().generateScript(
            forPackage: description,
            packageRoot: tempRoot,
            with: configuration,
            sdkPath: nil
        )
        let nodes = try #require(script.layoutGraph?.nodes)
        let httpClient = try #require(nodes.first { $0.label == "HttpClient" })
        let loginView = try #require(nodes.first { $0.label == "LoginView" })
        #expect(httpClient.module == "Networking")
        #expect(loginView.module == "UI")
    }

    @Test("PlantUML output includes the module name as an additional stereotype")
    func plantUMLIncludesModuleStereotype() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spm-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let dir = tempRoot.appendingPathComponent("Sources/Networking", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "class HttpClient {}".write(
            to: dir.appendingPathComponent("HttpClient.swift"),
            atomically: true, encoding: .utf8
        )

        let description = SPMPackageDescription(
            name: "Demo",
            targets: [
                SPMTargetDescription(
                    name: "Networking", kind: .library,
                    path: "Sources/Networking",
                    sources: ["HttpClient.swift"], dependencies: []
                ),
            ]
        )

        var configuration = Configuration.default
        configuration.format = .plantuml
        let script = ClassDiagramGenerator().generateScript(
            forPackage: description,
            packageRoot: tempRoot,
            with: configuration,
            sdkPath: nil
        )
        #expect(script.text.contains("<<Networking>>"))
    }

    @Test("Mermaid output includes the module name as an additional stereotype")
    func mermaidIncludesModuleStereotype() throws {
        let (description, packageRoot) = try Self.makeSingleTargetPackage(named: "Networking")
        defer { try? FileManager.default.removeItem(at: packageRoot) }

        var configuration = Configuration.default
        configuration.format = .mermaid
        let script = ClassDiagramGenerator().generateScript(
            forPackage: description,
            packageRoot: packageRoot,
            with: configuration,
            sdkPath: nil
        )
        #expect(script.text.contains("<<Networking>>"))
    }

    @Test("Nomnoml output includes the module name as an additional stereotype")
    func nomnomlIncludesModuleStereotype() throws {
        let (description, packageRoot) = try Self.makeSingleTargetPackage(named: "Networking")
        defer { try? FileManager.default.removeItem(at: packageRoot) }

        var configuration = Configuration.default
        configuration.format = .nomnoml
        let script = ClassDiagramGenerator().generateScript(
            forPackage: description,
            packageRoot: packageRoot,
            with: configuration,
            sdkPath: nil
        )
        #expect(script.text.contains("<<Networking>>"))
    }

    /// Build a temp directory with a single `Sources/<target>/<target>.swift`
    /// holding a stub class declaration, plus a matching SPM description.
    private static func makeSingleTargetPackage(
        named targetName: String
    ) throws -> (SPMPackageDescription, URL) {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spm-test-\(UUID().uuidString)", isDirectory: true)
        let targetDir = tempRoot
            .appendingPathComponent("Sources/\(targetName)", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        try "class HttpClient {}".write(
            to: targetDir.appendingPathComponent("HttpClient.swift"),
            atomically: true, encoding: .utf8
        )
        let description = SPMPackageDescription(
            name: "Demo",
            targets: [
                SPMTargetDescription(
                    name: targetName, kind: .library,
                    path: "Sources/\(targetName)",
                    sources: ["HttpClient.swift"], dependencies: []
                ),
            ]
        )
        return (description, tempRoot)
    }
}
