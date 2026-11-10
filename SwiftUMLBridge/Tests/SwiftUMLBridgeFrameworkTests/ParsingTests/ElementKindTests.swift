@testable import SwiftUMLBridgeFramework
import Testing

@Suite("ElementKind")
struct ElementKindTests {

    @Test("actor raw value matches SourceKitten kind string")
    func actorRawValue() {
        #expect(ElementKind.actor.rawValue == "source.lang.swift.decl.actor")
    }

    @Test("macro raw value matches SourceKitten kind string")
    func macroRawValue() {
        #expect(ElementKind.macro.rawValue == "source.lang.swift.decl.macro")
    }

    @Test("unknown raw value falls back to .other")
    func unknownFallback() {
        let kind = ElementKind(rawValue: "source.lang.swift.decl.nonexistent")
        #expect(kind == .other)
    }

    @Test("class raw value round-trips")
    func classRawValue() {
        let kind = ElementKind(rawValue: "source.lang.swift.decl.class")
        #expect(kind == .class)
    }

    @Test("struct raw value round-trips")
    func structRawValue() {
        let kind = ElementKind(rawValue: "source.lang.swift.decl.struct")
        #expect(kind == .struct)
    }

    @Test("protocol raw value round-trips")
    func protocolRawValue() {
        let kind = ElementKind(rawValue: "source.lang.swift.decl.protocol")
        #expect(kind == .protocol)
    }

    @Test("enum raw value round-trips")
    func enumRawValue() {
        let kind = ElementKind(rawValue: "source.lang.swift.decl.enum")
        #expect(kind == .enum)
    }
}
