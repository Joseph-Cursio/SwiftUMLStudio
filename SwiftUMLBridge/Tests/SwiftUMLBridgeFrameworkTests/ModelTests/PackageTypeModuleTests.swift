import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

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
            (name: "Core", files: [(name: "Format.swift", source: "public enum Format { case plain }")]),
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
            (name: "Zed", files: [(name: "Service+Sendable.swift", source: "extension Service: Sendable {}")]),
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
                (name: "Outer+Deep.swift", source: "extension Outer { class Deep {} }"),
            ]),
            (name: "Core", files: [
                (name: "Outer.swift", source: "enum Outer { class Inner {}\n enum Mid { class Inner {} } }")
            ]),
            (name: "Zed", files: [(name: "Subclasses.swift", source: """
                class Sub: Outer.Inner {}
                class Sub2: Outer.Deep {}
                class Sub3: Outer.Mid.Inner {}
                """)]),
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
