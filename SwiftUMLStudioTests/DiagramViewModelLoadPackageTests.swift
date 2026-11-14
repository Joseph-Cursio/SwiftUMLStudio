import Foundation
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

@Suite("DiagramViewModel.loadPackage")
@MainActor
struct DiagramViewModelLoadPackageTests {

    /// Creates a minimal SPM package on disk and returns its root URL. Caller
    /// is responsible for cleaning it up.
    private func makeMiniPackage() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("studio-spm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources/Demo", isDirectory: true),
            withIntermediateDirectories: true
        )
        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "Demo",
            targets: [.target(name: "Demo")]
        )
        """.write(
            to: root.appendingPathComponent("Package.swift"),
            atomically: true, encoding: .utf8
        )
        try "class Foo {}".write(
            to: root.appendingPathComponent("Sources/Demo/Foo.swift"),
            atomically: true, encoding: .utf8
        )
        return root
    }

    @Test("loadPackage stores the description and replaces selectedPaths")
    func loadPackageStoresDescription() async throws {
        let root = try makeMiniPackage()
        defer { try? FileManager.default.removeItem(at: root) }

        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        await viewModel.loadPackage(at: root)

        #expect(viewModel.packageRoot == root)
        #expect(viewModel.packageDescription?.name == "Demo")
        #expect(viewModel.packageLoadError == nil)
        // selectedPaths is replaced with the package's source files
        #expect(viewModel.selectedPaths.contains { $0.hasSuffix("Sources/Demo/Foo.swift") })
    }

    @Test("loadPackage on a missing directory sets packageLoadError")
    func loadPackageMissingDirectorySetsError() async {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        let bogus = URL(fileURLWithPath: "/this/path/does/not/exist-\(UUID().uuidString)")
        await viewModel.loadPackage(at: bogus)
        #expect(viewModel.packageDescription == nil)
        #expect(viewModel.packageLoadError != nil)
    }

    @Test("unloadPackage clears the package state")
    func unloadPackageClearsState() async throws {
        let root = try makeMiniPackage()
        defer { try? FileManager.default.removeItem(at: root) }

        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        await viewModel.loadPackage(at: root)
        #expect(viewModel.packageDescription != nil)

        viewModel.unloadPackage()
        #expect(viewModel.packageRoot == nil)
        #expect(viewModel.packageDescription == nil)
        #expect(viewModel.packageLoadError == nil)
    }
}
