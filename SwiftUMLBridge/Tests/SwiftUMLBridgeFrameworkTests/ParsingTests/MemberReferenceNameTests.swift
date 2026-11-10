import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftUMLBridgeFramework
import Testing

/// A member named after a `.` is read as its declaration is: a keyword written bare there gets
/// the backticks its declaration needs, and every other name reads as `canonicalName` (#130).
@Suite("Member names read after a dot")
struct MemberReferenceNameTests {
    static let spellings: [(String, String)] = [
        ("default", "`default`"), ("`default`", "`default`"), ("import", "`import`"), ("class", "`class`"),
        ("helper", "helper"), ("`helper`", "helper"), ("open", "open"), ("async", "async"),
        ("init", "init"), ("self", "self"), ("Type", "Type"), ("`Type`", "`Type`"), ("`go now`", "`go now`"),
    ]

    @Test("the name after x. reads as its declaration does", arguments: spellings)
    func memberReferenceName(spelling: String, expected: String) throws {
        let file = Parser.parse(source: "x.\(spelling)")
        let item = try #require(file.statements.first?.item.as(ExprSyntax.self))
        let member = try #require(item.as(MemberAccessExprSyntax.self))
        #expect(member.declName.baseName.memberReferenceName == expected)
    }

    @Test("a member name typed in reads as one written after a dot", arguments: spellings + [
        ("", ""), ("go now", "go now")
    ])
    func canonicalMemberIdentifier(spelling: String, expected: String) {
        #expect(spelling.canonicalMemberIdentifier == expected)
    }

    @Test("listedEntryPoint escapes a keyword method typed bare")
    func listedEntryPoint() {
        let listed = CallGraphExtractor.listedEntryPoint(type: "`Keyed`", method: "default")
        #expect(listed.type == "Keyed" && listed.method == "`default`")
    }

    @Test("traverse follows a bare keyword callee, and an entry typed bare, into the escaped method")
    func traverseNormalisesMethod() {
        let edges = [
            CallEdge(callerType: "Keyed", callerMethod: "start", calleeType: "Keyed", calleeMethod: "default",
                     isAsync: false, isUnresolved: false),
            CallEdge(callerType: "Keyed", callerMethod: "`default`", calleeType: "Keyed", calleeMethod: "helper",
                     isAsync: false, isUnresolved: false),
        ]
        let graph = CallGraph(edges: edges)
        #expect(graph.traverse(from: "Keyed", entryMethod: "start", maxDepth: 3).map(\.calleeMethod)
            == ["default", "helper"])
        #expect(graph.traverse(from: "Keyed", entryMethod: "default", maxDepth: 3).map(\.calleeMethod) == ["helper"])
    }
}
