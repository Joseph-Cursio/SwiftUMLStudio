import Testing
@testable import SwiftUMLBridgeFramework

// Actor declarations are now parsed correctly via SyntaxStructureBuilder (SwiftSyntax).
// ActorDeclSyntax maps to ElementKind.actor, replacing the previous SourceKit workaround
// where actors were misclassified as source.lang.swift.decl.class.

@Suite("ActorKind")
struct ActorKindDiagnosticTests {

    @Test("actor source parses with kind .actor")
    func actorParsesAsActor() {
        let source = "actor ImageCache { var count: Int = 0 }"
        let structure = SyntaxStructure.create(from: source)
        let item = structure?.substructure?.first
        #expect(item?.kind == .actor)
        #expect(item?.name == "ImageCache")
    }

    @Test("actor appears in PlantUML output with actor stereotype")
    func actorAppearsWithActorStereotype() {
        let source = "actor ImageCache { var count: Int = 0 }"
        let script = ClassDiagramGenerator().generateScript(for: source)
        #expect(script.text.contains("ImageCache"))
        #expect(script.text.contains("actor"))
        #expect(script.text.hasPrefix("@startuml"))
        #expect(script.text.hasSuffix("@enduml"))
    }

    @Test("ElementKind.actor raw value is the SourceKit actor kind string")
    func actorKindRawValueIsCorrect() {
        #expect(ElementKind.actor.rawValue == "source.lang.swift.decl.actor")
    }
}
