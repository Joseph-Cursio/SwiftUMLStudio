import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// A module-qualified name, `ModA.Foo.V`, means the member of ModA's `Foo` that the writer's
/// module loads, as the bare `Foo.V` does. Two modules each add a `V` to `Foo`; the writer
/// imports one. The lookup took whichever was read first, so the edge could end on a member the
/// writer never sees, and renaming a target flipped it (#245). Each case builds with swiftc, which
/// resolves the member only the expected supertype has.
@Suite("A module-qualified name reads only the members the writer's module loads")
struct ModuleQualifiedLoadsTests {
    typealias File = ImportAwareRankTests.File
    typealias Case = ImportAwareRankTests.Case

    private static let bareFoo = File(module: "ModA", source: "public struct Foo {\n    public init() {}\n}\n")

    /// ModB's `V`, a class nested in `Foo`, spelling the extension `extendedAs`.
    private static func classAdded(as extendedAs: String) -> File {
        File(module: "ModB", source: """
            import ModA

            extension \(extendedAs) {
                open class V {
                    public init() {}
                    public func vOnly() {}
                }
            }
            """)
    }

    /// ModD's `V`, a typealias of its top-level `Other`, spelling the extension `extendedAs`.
    private static func aliasAdded(as extendedAs: String) -> File {
        File(module: "ModD", source: """
            import ModA

            extension \(extendedAs) {
                public typealias V = Other
            }

            open class Other {
                public init() {}
                public func otherOnly() {}
            }
            """)
    }

    private static func writer(loading module: String) -> File {
        File(module: "ModC", source: "import ModA\nimport \(module)\n\nfinal class C: ModA.Foo.V {}\n")
    }

    static let cases: [Case] = ["ModA.Foo", "Foo"].flatMap { extended in
        [
            Case(name: "extension \(extended): the alias the writer loads, not the class", files: [
                bareFoo, classAdded(as: extended), aliasAdded(as: extended), writer(loading: "ModD")
            ], member: "otherOnly", hiddenLabel: nil),
            Case(name: "extension \(extended): the class the writer loads, not the alias", files: [
                bareFoo, classAdded(as: extended), aliasAdded(as: extended), writer(loading: "ModB")
            ], member: "vOnly", hiddenLabel: "ModA.Foo.V")
        ]
    }

    /// Each case is read with its files in the order given and reversed, so no answer comes from
    /// which module's member is recorded first.
    @Test("a module-qualified name means the member the writer loads", arguments: cases, [false, true])
    func meansTheMemberTheWriterLoads(_ testCase: Case, reversed: Bool) throws {
        try ImportAwareRankTests.expectMeans(testCase, reversed: reversed)
    }
}
