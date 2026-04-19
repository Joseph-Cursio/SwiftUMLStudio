//
//  ModelAndUtilityTests.swift
//  SwiftUMLStudioTests
//
//  Tests for DiagramMode, FileNode, and MermaidHTMLBuilder.
//

import Foundation
import Testing
@testable import SwiftUMLStudio

// MARK: - GCD dispatch helpers

private func runOnMain(_ block: @MainActor () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated(block)
    } else {
        DispatchQueue.main.sync { MainActor.assumeIsolated(block) }
    }
}

// MARK: - DiagramMode Tests

@Suite("DiagramMode")
struct DiagramModeTests {

    @Test("has exactly three cases")
    func allCasesCount() {
        runOnMain {
            #expect(DiagramMode.allCases.count == 3)
        }
    }

    @Test("classDiagram raw value is 'Class Diagram'")
    func classDiagramRawValue() {
        #expect(DiagramMode.classDiagram.rawValue == "Class Diagram")
    }

    @Test("sequenceDiagram raw value is 'Sequence Diagram'")
    func sequenceDiagramRawValue() {
        #expect(DiagramMode.sequenceDiagram.rawValue == "Sequence Diagram")
    }

    @Test("dependencyGraph raw value is 'Dependency Graph'")
    func dependencyGraphRawValue() {
        #expect(DiagramMode.dependencyGraph.rawValue == "Dependency Graph")
    }

    @Test("id equals rawValue for all cases")
    func idEqualsRawValue() {
        runOnMain {
            for mode in DiagramMode.allCases {
                #expect(mode.id == mode.rawValue)
            }
        }
    }

    @Test("allCases contains every case")
    func allCasesContainsEverything() {
        let cases = DiagramMode.allCases
        #expect(cases.contains(.classDiagram))
        #expect(cases.contains(.sequenceDiagram))
        #expect(cases.contains(.dependencyGraph))
    }

    @Test("can be initialized from raw value")
    func initFromRawValue() {
        #expect(DiagramMode(rawValue: "Class Diagram") == .classDiagram)
        #expect(DiagramMode(rawValue: "Sequence Diagram") == .sequenceDiagram)
        #expect(DiagramMode(rawValue: "Dependency Graph") == .dependencyGraph)
        #expect(DiagramMode(rawValue: "nonexistent") == nil)
    }
}

// MARK: - FileNode Tests

@Suite("FileNode")
struct FileNodeTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "FileNodeTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("buildTree returns empty for empty paths")
    func buildTreeEmpty() {
        runOnMain {
            let tree = FileNode.buildTree(from: [])
            #expect(tree.isEmpty)
        }
    }

    @Test("buildTree returns empty for nonexistent paths")
    func buildTreeNonexistent() {
        runOnMain {
            let tree = FileNode.buildTree(from: ["/nonexistent/path/file.swift"])
            #expect(tree.isEmpty)
        }
    }

    @Test("buildTree returns single file")
    func buildTreeSingleFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "Hello.swift")
        try "struct Hello {}".write(to: file, atomically: true, encoding: .utf8)

        runOnMain {
            let tree = FileNode.buildTree(from: [file.path()])
            #expect(tree.count == 1)
            #expect(tree[0].name == "Hello.swift")
            #expect(tree[0].isDirectory == false)
            #expect(tree[0].children == nil)
        }
    }

    @Test("buildTree filters out non-swift files in directories")
    func buildTreeFiltersNonSwift() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "struct A {}".write(to: dir.appending(path: "A.swift"), atomically: true, encoding: .utf8)
        try "not swift".write(to: dir.appending(path: "readme.md"), atomically: true, encoding: .utf8)
        try "{}".write(to: dir.appending(path: "config.json"), atomically: true, encoding: .utf8)

        runOnMain {
            let tree = FileNode.buildTree(from: [dir.path()])
            let allURLs = FileNode.allLeafURLs(from: tree)
            #expect(allURLs.count == 1)
            #expect(allURLs[0].lastPathComponent == "A.swift")
        }
    }

    @Test("buildTree creates directory nodes for nested structures")
    func buildTreeNested() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let subdir = dir.appending(path: "Models", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "struct A {}".write(to: dir.appending(path: "App.swift"), atomically: true, encoding: .utf8)
        try "struct B {}".write(to: subdir.appending(path: "Model.swift"), atomically: true, encoding: .utf8)

        runOnMain {
            let tree = FileNode.buildTree(from: [dir.path()])
            #expect(tree.count == 2) // Models/ directory + App.swift
            let dirNode = tree.first { $0.isDirectory }
            #expect(dirNode?.name == "Models")
            #expect(dirNode?.children?.count == 1)
            #expect(dirNode?.children?[0].name == "Model.swift")
        }
    }

    @Test("allLeafURLs collects all file URLs from nested tree")
    func allLeafURLsNested() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let subdir = dir.appending(path: "Sub", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "struct A {}".write(to: dir.appending(path: "A.swift"), atomically: true, encoding: .utf8)
        try "struct B {}".write(to: subdir.appending(path: "B.swift"), atomically: true, encoding: .utf8)

        runOnMain {
            let tree = FileNode.buildTree(from: [dir.path()])
            let urls = FileNode.allLeafURLs(from: tree)
            #expect(urls.count == 2)
        }
    }
}

// MARK: - MermaidHTMLBuilder Tests

@Suite("MermaidHTMLBuilder")
struct MermaidHTMLBuilderTests {

    // MARK: htmlEscape

    @Test("htmlEscape leaves plain text unchanged")
    func htmlEscapePlainText() {
        #expect(MermaidHTMLBuilder.htmlEscape("hello world") == "hello world")
    }

    @Test("htmlEscape replaces & with &amp;")
    func htmlEscapeAmpersand() {
        #expect(MermaidHTMLBuilder.htmlEscape("A & B") == "A &amp; B")
    }

    @Test("htmlEscape replaces < with &lt;")
    func htmlEscapeLessThan() {
        #expect(MermaidHTMLBuilder.htmlEscape("a < b") == "a &lt; b")
    }

    @Test("htmlEscape replaces > with &gt;")
    func htmlEscapeGreaterThan() {
        #expect(MermaidHTMLBuilder.htmlEscape("a > b") == "a &gt; b")
    }

    @Test("htmlEscape replaces all three characters in one string")
    func htmlEscapeAllSpecialChars() {
        #expect(MermaidHTMLBuilder.htmlEscape("<a & b>") == "&lt;a &amp; b&gt;")
    }

    @Test("htmlEscape escapes & before < and > to avoid double-escaping")
    func htmlEscapeOrderPreventDoubleEscape() {
        // If < were escaped first to &lt;, the & in &lt; could be re-escaped to &amp;lt;
        #expect(MermaidHTMLBuilder.htmlEscape("<") == "&lt;")
        #expect(MermaidHTMLBuilder.htmlEscape(">") == "&gt;")
    }

    @Test("htmlEscape handles empty string")
    func htmlEscapeEmpty() {
        #expect(MermaidHTMLBuilder.htmlEscape("") == "")
    }

    @Test("htmlEscape handles multiple consecutive special chars")
    func htmlEscapeConsecutive() {
        #expect(MermaidHTMLBuilder.htmlEscape("<<>>&&") == "&lt;&lt;&gt;&gt;&amp;&amp;")
    }

    // MARK: mermaidHTML

    @Test("mermaidHTML contains the escaped diagram text")
    func mermaidHTMLContainsDiagramText() {
        let html = MermaidHTMLBuilder.mermaidHTML("A -> B")
        #expect(html.contains("A -&gt; B"))
    }

    @Test("mermaidHTML contains mermaid div")
    func mermaidHTMLContainsMermaidDiv() {
        let html = MermaidHTMLBuilder.mermaidHTML("graph TD")
        #expect(html.contains("<div class=\"mermaid\">"))
    }

    @Test("mermaidHTML contains mermaid CDN script tag")
    func mermaidHTMLContainsScriptTag() {
        let html = MermaidHTMLBuilder.mermaidHTML("graph TD")
        #expect(html.contains("mermaid.min.js"))
    }

    @Test("mermaidHTML escapes XSS injection attempt")
    func mermaidHTMLEscapesInjection() {
        let html = MermaidHTMLBuilder.mermaidHTML("</div><script>evil()</script>")
        #expect(html.contains("<script>evil()") == false)
        #expect(html.contains("&lt;/div&gt;&lt;script&gt;evil()&lt;/script&gt;"))
    }
}
