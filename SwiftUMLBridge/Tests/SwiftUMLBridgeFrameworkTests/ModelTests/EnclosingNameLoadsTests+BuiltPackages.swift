@testable import SwiftUMLBridgeFramework
import Testing

/// Packages built by hand for `EnclosingNameLoadsTests`, each checked with swiftc by calling the
/// member only the meant supertype has.
extension EnclosingNameLoadsTests {
    /// ModC's `C`, nested in `extension \(extended)`, in a file that imports `modules`.
    static func extensionWriter(importing modules: [String], extending extended: String) -> File {
        let imports = modules.map { "import \($0)\n" }.joined()
        return File(module: "ModC", source: "\(imports)\nextension \(extended) {\n    final class C: V {}\n}\n")
    }

    /// Packages built by hand, each checked with swiftc by calling the member only the meant
    /// supertype has.
    static let builtCases: [Case] = [
        Case(
            name: "a re-export: with the feature, the alias of the module the writer's import re-exports",
            files: [
                bareFoo, classAdded(as: "Foo"), aliasAdded(as: "Foo"),
                File(module: "ModE", source: "@_exported import ModD\n"), holder(importing: "ModB"),
                extensionWriter(importing: ["ModA", "ModE"], extending: "Foo"),
            ],
            member: "otherOnly", line: "Other <|-- Foo.C : inherits", memberImportVisibility: ["ModC"]
        ),
    ] + fallThroughCases + [
        Case(
            name: "another module's own Foo with a V, which the writer's extension does not extend",
            files: [
                bareFoo, classAdded(as: "ModA.Foo"), holder(importing: "ModD"),
                File(module: "ModD", source: """
                    public struct Foo {
                        public init() {}
                        open class V {
                            public init() {}
                            public func dOnly() {}
                        }
                    }

                    public struct DThing {
                        public init() {}
                    }
                    """),
                extensionWriter(importing: ["ModA", "ModB"], extending: "Foo"),
            ],
            member: "vOnly", line: "ModA.Foo.V <|-- Foo.C : inherits", memberImportVisibility: []
        ),
        Case(
            name: "a type body, whose V an extension in its own module spells with the module",
            files: [
                File(module: "ModD", source: """
                    open class V {
                        public init() {}
                        public func topOnly() {}
                    }
                    """),
                File(module: "ModC", source: """
                    extension ModC.Bar {
                        class V {
                            func barOnly() {}
                        }
                    }
                    """),
                File(module: "ModC", source: "import ModD\n\nstruct Bar {\n    final class C: V {}\n}\n"),
            ],
            member: "barOnly", line: "ModC.Bar.V <|-- Bar.C : inherits", memberImportVisibility: []
        ),
        Case(
            name: "extension Foo.Inner, which Swift does not read Foo's members from",
            files: [
                File(module: "ModA", source: """
                    public struct Foo {
                        public init() {}
                        public struct Inner {
                            public init() {}
                        }
                    }
                    """),
                File(module: "ModB", source: """
                    import ModA

                    extension ModA.Foo.Inner {
                        open class V {
                            public init() {}
                            public func vOnly() {}
                        }
                    }
                    """),
                aliasAdded(as: "ModA.Foo"),
                File(module: "ModC", source: "class V {\n    func topOnly() {}\n}\n"),
                extensionWriter(importing: ["ModA", "ModD"], extending: "Foo.Inner"),
            ],
            member: "topOnly", line: "V <|-- Foo.Inner.C : inherits", memberImportVisibility: []
        ),
        Case(
            name: "only another module's extension, spelled with the module, adds the V",
            files: [
                bareFoo, classAdded(as: "ModA.Foo"), extensionWriter(importing: ["ModA", "ModB"], extending: "Foo"),
            ],
            member: "vOnly", line: "ModA.Foo.V <|-- Foo.C : inherits", memberImportVisibility: []
        ),
        Case(
            name: "a struct in the extension, whose own S another module's Foo.S does not stand for",
            files: [
                bareFoo, aliasAdded(as: "Foo"),
                File(module: "ModB", source: """
                    import ModA

                    extension ModA.Foo {
                        public struct S {
                            open class V {
                                public init() {}
                                public func vOnly() {}
                            }
                        }
                    }
                    """),
                File(module: "ModC", source: """
                    import ModA
                    import ModB
                    import ModD

                    extension Foo {
                        struct S {
                            final class C: V {}
                        }
                    }
                    """),
            ],
            member: "otherOnly", line: "Other <|-- Foo.S.C : inherits", memberImportVisibility: []
        ),
        Case(
            name: "a re-exporter's own Foo, which shadows ModA's and has no V, so the name is ModC's",
            files: [
                bareFoo, classAdded(as: "Foo"),
                reexporter("ModE", of: "ModA"),
                File(module: "ModC", source: """
                    open class V {
                        public init() {}
                        public func cOnly() {}
                    }
                    """),
                extensionWriter(importing: ["ModE", "ModB"], extending: "Foo"),
            ],
            member: "cOnly", line: "V <|-- Foo.C : inherits", memberImportVisibility: []
        ),
        Case(
            name: "a re-exporter's own Foo, which shadows Core's and has no X, so the name is App's",
            files: [
                File(module: "Core", source: """
                    public struct Foo {
                        public init() {}
                        open class X {
                            public init() {}
                            public func coreOnly() {}
                        }
                    }
                    """),
                reexporter("Umbrella", of: "Core"),
                File(module: "App", source: """
                    import Umbrella

                    class X {
                        init() {}
                        func appOnly() {}
                    }

                    extension Foo {
                        final class W: X {}
                    }
                    """),
            ],
            member: "appOnly", line: "X <|-- Foo.W : inherits", memberImportVisibility: []
        ),
    ] + twoFooCases

    /// `module`, which re-exports `reexported` and declares a `Foo` of its own, with no members.
    private static func reexporter(_ module: String, of reexported: String) -> File {
        File(module: module, source: """
            @_exported import \(reexported)

            public struct Foo {
                public init() {}
            }
            """)
    }

    /// ModA and ModZ each declare a `Foo`, which ModB and ModY each give a `V`; one file of ModC
    /// extends ModA's and another ModZ's, so each writer starts at its own file's `Foo`.
    private static var twoFooCases: [Case] {
        func adding(_ module: String, to owner: String, member: String) -> File {
            File(module: module, source: """
                import \(owner)

                extension \(owner).Foo {
                    open class V {
                        public init() {}
                        public func \(member)() {}
                    }
                }
                """)
        }
        let files = [
            bareFoo, File(module: "ModZ", source: "public struct Foo {\n    public init() {}\n}\n"),
            adding("ModB", to: "ModA", member: "vOnly"), adding("ModY", to: "ModZ", member: "zOnly"),
            extensionWriter(importing: ["ModA", "ModB"], extending: "Foo"),
            File(module: "ModC", source: "import ModZ\nimport ModY\n\nextension Foo {\n    final class D: V {}\n}\n"),
        ]
        return [
            Case(
                name: "two modules' Foo, the writer in the file that extends ModA's",
                files: files, member: "vOnly", line: "ModA.Foo.V <|-- Foo.C : inherits", memberImportVisibility: []
            ),
            Case(
                name: "two modules' Foo, the writer in the file that extends ModZ's",
                files: files, member: "zOnly", line: "ModZ.Foo.V <|-- Foo.D : inherits", memberImportVisibility: []
            ),
        ]
    }

    /// ModC's own top-level `V`, and a writer that imports neither ModB nor ModD while another
    /// file imports ModB: with the feature, `Foo` has no member `V` the writer sees, so the name
    /// is ModC's; without it, ModB's member is.
    private static var fallThroughCases: [Case] {
        let ownV = File(module: "ModC", source: """
            open class V {
                public init() {}
                public func cOnly() {}
            }
            """)
        return spellings.flatMap { extended in
            [true, false].map { enabled in
                let means = enabled ? "V" : (extended == "ModA.Foo" ? "ModA.Foo.V" : "Foo.V")
                return Case(
                    name: "extension \(extended), the writer imports only ModA, "
                        + (enabled ? "with the feature: ModC's own V" : "without the feature: ModB's member"),
                    files: [
                        bareFoo, classAdded(as: extended), aliasAdded(as: extended), holder(importing: "ModB"), ownV,
                        extensionWriter(importing: ["ModA"], extending: "Foo"),
                    ],
                    member: enabled ? "cOnly" : "vOnly", line: "\(means) <|-- Foo.C : inherits",
                    memberImportVisibility: enabled ? ["ModC"] : []
                )
            }
        }
    }
}
