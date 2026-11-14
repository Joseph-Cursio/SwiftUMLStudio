@testable import SwiftUMLBridgeFramework
import Testing

@Suite("SourceLocation")
struct SourceLocationTests {

    @Test("stores constructor arguments")
    func storesArguments() {
        let location = SourceLocation(filePath: "/Users/me/Foo.swift", line: 12, column: 5)
        #expect(location.filePath == "/Users/me/Foo.swift")
        #expect(location.line == 12)
        #expect(location.column == 5)
    }

    @Test("two locations with the same fields are equal and hash equally")
    func equalityAndHashing() {
        let lhs = SourceLocation(filePath: "/x.swift", line: 1, column: 1)
        let rhs = SourceLocation(filePath: "/x.swift", line: 1, column: 1)
        #expect(lhs == rhs)
        #expect(lhs.hashValue == rhs.hashValue)
    }

    @Test("different lines compare unequal")
    func differingLinesAreUnequal() {
        let lhs = SourceLocation(filePath: "/x.swift", line: 1, column: 1)
        let rhs = SourceLocation(filePath: "/x.swift", line: 2, column: 1)
        #expect(lhs != rhs)
    }
}
