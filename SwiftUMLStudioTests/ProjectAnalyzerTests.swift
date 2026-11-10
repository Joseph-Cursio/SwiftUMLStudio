import Foundation
@testable import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

// MARK: - Test fixture helpers

private func createTestProject(files: [String: String]) throws -> String {
    let tempDir = NSTemporaryDirectory() + "SwiftUMLStudioTest-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    for (name, contents) in files {
        let filePath = tempDir + "/" + name
        try contents.write(toFile: filePath, atomically: true, encoding: .utf8)
    }
    return tempDir
}

// MARK: - ProjectAnalyzer Tests

@MainActor
struct ProjectAnalyzerTests {

    @Test("analyze returns empty summary for empty paths")
    func emptyPaths() {
        let summary = ProjectAnalyzer.analyze(paths: [])
        #expect(summary.totalFiles == 0)
        #expect(summary.totalTypes == 0)
    }

    @Test("analyze returns empty summary for nonexistent paths")
    func nonexistentPath() {
        let summary = ProjectAnalyzer.analyze(paths: ["/nonexistent/path"])
        #expect(summary.totalFiles == 0)
        #expect(summary.totalTypes == 0)
        #expect(summary.totalRelationships == 0)
    }

    @Test("analyze returns correct file count for directory")
    func fileCount() throws {
        let dir = try createTestProject(files: [
            "TypeA.swift": "class TypeA {}",
            "TypeB.swift": "struct TypeB {}",
            "TypeC.swift": "enum TypeC { case one }"
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let summary = ProjectAnalyzer.analyze(paths: [dir])
        #expect(summary.totalFiles == 3)
    }

    @Test("analyze returns correct file count for individual files")
    func fileCountIndividual() throws {
        let dir = try createTestProject(files: [
            "Single.swift": "struct Single {}"
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let filePath = dir + "/Single.swift"
        let summary = ProjectAnalyzer.analyze(paths: [filePath])
        #expect(summary.totalFiles == 1)
    }

    @Test("analyze counts types by kind")
    func typeBreakdown() throws {
        let dir = try createTestProject(files: [
            "Types.swift": """
            class MyClass {}
            struct MyStruct {}
            struct AnotherStruct {}
            enum MyEnum { case val }
            protocol MyProtocol {}
            """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let summary = ProjectAnalyzer.analyze(paths: [dir])
        #expect(summary.totalTypes == 5)
        #expect(summary.typeBreakdown["Classs"] == 1)
        #expect(summary.typeBreakdown["Structs"] == 2)
        #expect(summary.typeBreakdown["Enums"] == 1)
        #expect(summary.typeBreakdown["Protocols"] == 1)
    }

    @Test("analyze detects inheritance relationships")
    func relationships() throws {
        let dir = try createTestProject(files: [
            "Hierarchy.swift": """
            protocol Drawable { func draw() }
            class Shape: Drawable { func draw() {} }
            class Circle: Shape {}
            """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let summary = ProjectAnalyzer.analyze(paths: [dir])
        #expect(summary.totalRelationships >= 2,
                "Expected at least 2 relationships (Shape: Drawable, Circle: Shape)")
    }

    @Test("analyze detects module imports")
    func moduleImports() throws {
        let dir = try createTestProject(files: [
            "Imports.swift": """
            import Foundation
            import SwiftUI
            class ViewModel {}
            """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let summary = ProjectAnalyzer.analyze(paths: [dir])
        #expect(summary.moduleImports.contains("Foundation"))
        #expect(summary.moduleImports.contains("SwiftUI"))
    }

    @Test("analyze finds entry points")
    func entryPoints() throws {
        let dir = try createTestProject(files: [
            "Service.swift": """
            class UserService {
                func fetchUser() {}
                func saveUser() {}
            }
            """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let summary = ProjectAnalyzer.analyze(paths: [dir])
        #expect(summary.entryPoints.isEmpty == false,
                "Expected entry points from UserService methods")
    }

    @Test("analyze identifies top connected types")
    func topConnectedTypes() throws {
        let dir = try createTestProject(files: [
            "Hub.swift": """
            protocol Hub {}
            class ServiceA: Hub {}
            class ServiceB: Hub {}
            class ServiceC: Hub {}
            """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let summary = ProjectAnalyzer.analyze(paths: [dir])
        let topNames = summary.topConnectedTypes.map(\.name)
        #expect(topNames.contains("Hub"),
                "Hub should be a top connected type since 3 types conform to it")
    }

    // MARK: - Module-aware analysis (analyze(package:))

    @Test("analyze(package:) returns one ModuleSummary per non-test target")
    func packageBreakdownTargets() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalyzerPkgTests-\(UUID().uuidString)", isDirectory: true)
        let coreDir = temp.appendingPathComponent("Sources/Core")
        let appDir = temp.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: coreDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        try "public protocol Service {}".write(
            to: coreDir.appendingPathComponent("Service.swift"),
            atomically: true, encoding: .utf8
        )
        try "public struct HTTPClient: Service {}".write(
            to: appDir.appendingPathComponent("HTTPClient.swift"),
            atomically: true, encoding: .utf8
        )

        let description = SPMPackageDescription(
            name: "Demo",
            targets: [
                SPMTargetDescription(
                    name: "Core", kind: .library, path: "Sources/Core",
                    sources: ["Service.swift"], dependencies: []
                ),
                SPMTargetDescription(
                    name: "App", kind: .executable, path: "Sources/App",
                    sources: ["HTTPClient.swift"], dependencies: ["Core"]
                ),
                SPMTargetDescription(
                    name: "DemoTests", kind: .test, path: "Tests/DemoTests",
                    sources: [], dependencies: ["App"]
                )
            ]
        )

        let summary = ProjectAnalyzer.analyze(package: description, packageRoot: temp)
        let names = summary.moduleBreakdown.map(\.name)
        #expect(names == ["App", "Core"], "Test target should be excluded")
    }

    @Test("analyze(package:) populates kind, file, type, and dependency counts")
    func packageBreakdownCounts() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalyzerPkgTests-\(UUID().uuidString)", isDirectory: true)
        let netDir = temp.appendingPathComponent("Sources/Networking")
        try FileManager.default.createDirectory(at: netDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        try """
        public struct HTTPClient {}
        public protocol Service {}
        """.write(
            to: netDir.appendingPathComponent("HTTPClient.swift"),
            atomically: true, encoding: .utf8
        )

        let description = SPMPackageDescription(
            name: "Demo",
            targets: [
                SPMTargetDescription(
                    name: "Networking", kind: .library, path: "Sources/Networking",
                    sources: ["HTTPClient.swift"],
                    dependencies: ["Core", "Logging"]
                )
            ]
        )

        let summary = ProjectAnalyzer.analyze(package: description, packageRoot: temp)
        let module = try #require(summary.moduleBreakdown.first { $0.name == "Networking" })
        #expect(module.kind == .library)
        #expect(module.fileCount == 1)
        #expect(module.typeCount == 2)
        #expect(module.outgoingTargetDependencies == 2)
    }

    @Test("analyze(paths:) leaves moduleBreakdown empty")
    func pathBasedAnalysisHasEmptyBreakdown() throws {
        let dir = try createTestProject(files: [
            "Foo.swift": "struct Foo {}"
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let summary = ProjectAnalyzer.analyze(paths: [dir])
        #expect(summary.moduleBreakdown.isEmpty)
    }
}

// MARK: - InsightEngine coverage gaps

@MainActor
struct InsightEngineCoverageTests {

    @Test("generates module import insight when 2+ modules present")
    func moduleImportInsight() {
        let summary = ProjectSummary(
            totalFiles: 5, totalTypes: 10,
            typeBreakdown: ["Classes": 10],
            totalRelationships: 3,
            moduleImports: ["Foundation", "SwiftUI", "Combine"],
            topConnectedTypes: [],
            cycleWarnings: [],
            entryPoints: [],
            stateMachines: []
        )
        let insights = InsightEngine.generate(from: summary)
        let moduleInsight = insights.first { $0.title.contains("modules imported") }
        #expect(moduleInsight != nil, "Expected a module import insight")
    }

    @Test("generates no-relationships insight when types exist but no edges")
    func noRelationshipsInsight() {
        let summary = ProjectSummary(
            totalFiles: 3, totalTypes: 5,
            typeBreakdown: ["Structs": 5],
            totalRelationships: 0,
            moduleImports: [],
            topConnectedTypes: [],
            cycleWarnings: [],
            entryPoints: [],
            stateMachines: []
        )
        let insights = InsightEngine.generate(from: summary)
        let noRels = insights.first { $0.title.contains("No type relationships") }
        #expect(noRels != nil, "Expected a no-relationships insight")
    }

    @Test("no insights generated for empty project")
    func emptyProjectInsights() {
        let summary = ProjectSummary(
            totalFiles: 0, totalTypes: 0,
            typeBreakdown: [:],
            totalRelationships: 0,
            moduleImports: [],
            topConnectedTypes: [],
            cycleWarnings: [],
            entryPoints: [],
            stateMachines: []
        )
        let insights = InsightEngine.generate(from: summary)
        #expect(insights.isEmpty)
    }
}
