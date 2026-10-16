import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// A package written to a temporary directory. Its description lists the targets, and each
/// target's sources, in the order given, or in the reverse order. A target lives at
/// `Sources/<name>` unless `paths` gives it another directory.
private struct TemporaryPackage {
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

/// Package mode walked its files in the hash order of `sourceFileToModuleMap`, which Swift seeds
/// per process and per dictionary, so the class diagram and dependency graph of the same package
/// changed from run to run, and from call to call within one (#70). Files are now walked in path
/// order.
@Suite("Package mode walks its files in path order")
struct PackageModeOrderTests {

    /// `Core` declares `Format`, which `App` and `Zed` extend, and `App` and `Core` both extend
    /// `String`. Enough files that hash order was all but certain to differ across the ten calls.
    fileprivate static func package() throws -> TemporaryPackage {
        let types = ["A", "B", "C", "D", "E", "F"].map { (name: "\($0).swift", source: "struct Type\($0) {}") }
        return try TemporaryPackage([
            (name: "Core", files: types + [
                (name: "Format.swift", source: "public enum Format: String { case plain }"),
                (name: "StringCore.swift", source: "extension String { func core() {} }")
            ]),
            (name: "App", files: [
                (name: "Format+CLI.swift", source: "extension Format: CustomStringConvertible {}"),
                (name: "StringApp.swift", source: "extension String { func app() {} }")
            ]),
            (name: "Zed", files: [(name: "Format+ID.swift", source: "extension Format: Identifiable {}")])
        ])
    }

    private func classDiagram(
        _ description: SPMPackageDescription, at root: URL, format: DiagramFormat = .plantuml,
        extensions: ExtensionVisualization = .all
    ) -> String {
        let configuration = Configuration(elements: ElementOptions(showExtensions: extensions), format: format)
        return ClassDiagramGenerator()
            .generateScript(forPackage: description, packageRoot: root, with: configuration, sdkPath: nil).text
    }

    private func dependencyGraph(
        _ description: SPMPackageDescription, at root: URL, format: DiagramFormat = .plantuml
    ) -> String {
        DependencyGraphGenerator().generateScript(
            forPackage: description, packageRoot: root, mode: .types, with: Configuration(format: format)
        ).text
    }

    /// Sorted by path, not by module, and with `<`, which puts every capital before every small
    /// letter: `Sources/SwiftUMLBridgeFramework` before `Sources/swiftumlbridge`, as in this repo.
    @Test("the files come in path order, without the test targets")
    func sourceFilesInPathOrder() {
        let description = SPMPackageDescription(name: "Demo", targets: [
            SPMTargetDescription(name: "Zed", kind: .library, path: "Sources/Zed",
                                 sources: ["B.swift", "A.swift"], dependencies: []),
            SPMTargetDescription(name: "ZedTests", kind: .test, path: "Tests/ZedTests",
                                 sources: ["ATests.swift"], dependencies: ["Zed"]),
            SPMTargetDescription(name: "App", kind: .executable, path: "Sources/app",
                                 sources: ["Main.swift"], dependencies: ["Zed"]),
            SPMTargetDescription(name: "Core", kind: .library, path: "Sources/Aa",
                                 sources: ["Core.swift"], dependencies: [])
        ])
        let root = URL(fileURLWithPath: "/pkg")
        let files = description.sourceFilesInPathOrder(packageRoot: root)
        #expect(files.map(\.path) == [
            "/pkg/Sources/Aa/Core.swift", "/pkg/Sources/Zed/A.swift", "/pkg/Sources/Zed/B.swift",
            "/pkg/Sources/app/Main.swift"
        ])
        #expect(files.map(\.module) == ["Core", "Zed", "Zed", "App"])
        #expect(files.map(\.path) == description.sourceFileToModuleMap(packageRoot: root).keys.sorted())
    }

    @Test("a class diagram is the same on every call, whatever order the description lists", arguments: [
        DiagramFormat.plantuml, .mermaid, .nomnoml, .svg
    ], [ExtensionVisualization.all, .merged, .none])
    func classDiagramIsRepeatable(format: DiagramFormat, extensions: ExtensionVisualization) throws {
        let package = try Self.package()
        defer { package.remove() }
        let texts = Set([false, true].flatMap { reversed in
            (0..<5).map { _ in
                classDiagram(package.description(reversed: reversed), at: package.root, format: format,
                             extensions: extensions)
            }
        })
        #expect(texts.count == 1)
    }

    @Test("a dependency graph is the same on every call, whatever order the description lists", arguments: [
        DiagramFormat.plantuml, .mermaid, .nomnoml, .svg
    ])
    func dependencyGraphIsRepeatable(format: DiagramFormat) throws {
        let package = try Self.package()
        defer { package.remove() }
        let texts = Set([false, true].flatMap { reversed in
            (0..<5).map { _ in
                dependencyGraph(package.description(reversed: reversed), at: package.root, format: format)
            }
        })
        #expect(texts.count == 1)
    }

    /// Of the same-named declarations, the first keeps the bare alias, so which one that is, and
    /// the module drawn on it, followed hash order too.
    @Test("the first extension in path order keeps the bare alias", arguments: [false, true])
    func firstInPathOrderKeepsTheName(reversed: Bool) throws {
        let package = try Self.package()
        defer { package.remove() }
        let text = classDiagram(package.description(reversed: reversed), at: package.root)
        let strings = text.split(separator: "\n").filter { $0.hasPrefix("class \"String\"") }
        #expect(strings == [
            "class \"String\" as String << (X, orchid) extension >> <<App>> { ",
            "class \"String\" as String1 << (X, orchid) extension >> <<Core>> { "
        ])
    }

    /// The order is the files' paths, not the targets' names: `Core` lives in `Sources/Aa`.
    @Test("the bare alias goes to the first path, not the first target name", arguments: [false, true])
    func pathOrderIsNotNameOrder(reversed: Bool) throws {
        let package = try TemporaryPackage([
            (name: "App", files: [(name: "StringApp.swift", source: "extension String { func app() {} }")]),
            (name: "Core", files: [(name: "StringCore.swift", source: "extension String { func core() {} }")])
        ], paths: ["App": "Sources/Zz", "Core": "Sources/Aa"])
        defer { package.remove() }
        let text = classDiagram(package.description(reversed: reversed), at: package.root)
        #expect(text.split(separator: "\n").filter { $0.hasPrefix("class \"String\"") } == [
            "class \"String\" as String << (X, orchid) extension >> <<Core>> { ",
            "class \"String\" as String0 << (X, orchid) extension >> <<App>> { "
        ])
    }

    /// No target declares `String`, so `--merge-extensions` merges its extensions into the first
    /// one, and that box's module and member order followed hash order too.
    @Test("merged extensions keep path order", arguments: [false, true])
    func mergedExtensionsKeepPathOrder(reversed: Bool) throws {
        let package = try Self.package()
        defer { package.remove() }
        let text = classDiagram(package.description(reversed: reversed), at: package.root, extensions: .merged)
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let start = try #require(lines.firstIndex { $0.hasPrefix("class \"String\"") })
        #expect(Array(lines[start...].prefix(3))
            == ["class \"String\" as String << (X, orchid) extension >> <<App>> {", "~app", "~core"])
    }
}

/// `deps --types --package` tagged each type with the module of the last edge that named it, so a
/// type another target extended was labelled with that target, and which one followed hash order
/// (#70). Sorting alone would have made that stable, not right: the CLI target's path sorts after
/// the framework's, so `DiagramFormat` would always have been `<<swiftumlbridge>>`.
@Suite("deps --types --package tags a type with the module that declares it")
struct PackageTypeModuleTests {

    private func dependencyGraph(
        _ package: TemporaryPackage, reversed: Bool, format: DiagramFormat = .plantuml
    ) -> String {
        DependencyGraphGenerator().generateScript(
            forPackage: package.description(reversed: reversed), packageRoot: package.root, mode: .types,
            with: Configuration(format: format)
        ).text
    }

    /// `App` sorts before `Core` and `Zed` after it, so neither the first nor the last extension
    /// in path order can stand in for the declaration.
    @Test("an extended type keeps the module that declares it", arguments: [false, true])
    func extendedType(reversed: Bool) throws {
        let package = try PackageModeOrderTests.package()
        defer { package.remove() }
        #expect(dependencyGraph(package, reversed: reversed).contains("class \"Format\" as Format <<Core>>"))
        #expect(dependencyGraph(package, reversed: reversed, format: .mermaid)
            .contains("Format[\"Format<br/>«Core»\"]"))
    }

    /// Every edge carries its type's module, not only the last to name it: here the only edge
    /// comes from `App`, whose path sorts before that of `Core`, which declares the type.
    @Test("an extension's only edge carries the module that declares its type", arguments: [false, true])
    func extensionsOnlyEdge(reversed: Bool) throws {
        let package = try TemporaryPackage([
            (name: "App", files: [(name: "Format+CLI.swift", source: "extension Format: CustomStringConvertible {}")]),
            (name: "Core", files: [(name: "Format.swift", source: "public enum Format { case plain }")])
        ])
        defer { package.remove() }
        let text = dependencyGraph(package, reversed: reversed)
        #expect(text.contains("class \"Format\" as Format <<Core>>"), "\(text)")
    }

    @Test("a parent extended elsewhere keeps the module that declares it", arguments: [false, true])
    func extendedParent(reversed: Bool) throws {
        let package = try TemporaryPackage([
            (name: "App", files: [(name: "Ping.swift", source: "extension Service { func ping() {} }")]),
            (name: "Core", files: [(name: "Service.swift", source: "public protocol Service {}")]),
            (name: "Networking", files: [(name: "HTTPClient.swift", source: "struct HTTPClient: Service {}")]),
            (name: "Zed", files: [(name: "Service+Sendable.swift", source: "extension Service: Sendable {}")])
        ])
        defer { package.remove() }
        let text = dependencyGraph(package, reversed: reversed)
        #expect(text.contains("class \"Service\" as Service <<Core>>"), "\(text)")
        #expect(text.contains("class \"HTTPClient\" as HTTPClient <<Networking>>"), "\(text)")
    }

    @Test("a type no target declares takes the first module that extends it", arguments: [false, true])
    func undeclaredType(reversed: Bool) throws {
        let package = try PackageModeOrderTests.package()
        defer { package.remove() }
        #expect(dependencyGraph(package, reversed: reversed).contains("class \"String\" as String <<App>>"))
    }

    /// A nested type is a member, not one of a file's top-level items, so only its extension named
    /// it, and the module that extends it labelled it.
    @Test("a nested type keeps the module that declares it, in a type or in an extension", arguments: [false, true])
    func nestedType(reversed: Bool) throws {
        let package = try TemporaryPackage([
            (name: "App", files: [
                (name: "Inner+Sendable.swift", source: "extension Outer.Inner: Sendable {}"),
                (name: "MidInner+Sendable.swift", source: "extension Outer.Mid.Inner: Sendable {}"),
                (name: "Outer+Deep.swift", source: "extension Outer { class Deep {} }")
            ]),
            (name: "Core", files: [
                (name: "Outer.swift", source: "enum Outer { class Inner {}\n enum Mid { class Inner {} } }")
            ]),
            (name: "Zed", files: [(name: "Subclasses.swift", source: """
                class Sub: Outer.Inner {}
                class Sub2: Outer.Deep {}
                class Sub3: Outer.Mid.Inner {}
                """)])
        ])
        defer { package.remove() }
        let text = dependencyGraph(package, reversed: reversed)
        #expect(text.contains("class \"Outer.Inner\" as Outer.Inner <<Core>>"), "\(text)")
        #expect(text.contains("class \"Outer.Mid.Inner\" as Outer.Mid.Inner <<Core>>"), "\(text)")
        #expect(text.contains("class \"Outer.Deep\" as Outer.Deep <<App>>"), "\(text)")
    }

    @Test("the declaration wins whichever is recorded first")
    func declarationWinsInEitherOrder() {
        let declaration = SyntaxStructure(kind: .enum, name: "Format")
        let extensions = [
            SyntaxStructure(kind: .extension, name: "Format"), SyntaxStructure(kind: .extension, name: "Format")
        ]
        var extensionFirst = PackageTypeOwners()
        extensionFirst.record(extensions[0], in: "App")
        extensionFirst.record(declaration, in: "Core")
        extensionFirst.record(extensions[1], in: "Zed")
        var declarationFirst = PackageTypeOwners()
        declarationFirst.record(declaration, in: "Core")
        declarationFirst.record(extensions[0], in: "App")
        #expect(extensionFirst.module(of: "Format") == "Core")
        #expect(declarationFirst.module(of: "Format") == "Core")
        #expect(extensionFirst.module(of: "String") == nil)
    }
}
