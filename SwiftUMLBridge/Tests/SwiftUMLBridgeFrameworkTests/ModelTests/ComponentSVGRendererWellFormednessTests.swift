import Testing
@testable import SwiftUMLBridgeFramework

/// Parses `ComponentSVGRenderer` output as XML. The other `ComponentSVGRenderer` tests check
/// substrings, which a malformed document can still contain (#80).
@Suite("ComponentSVGRenderer — well-formedness")
struct ComponentSVGRendererWellFormednessTests {

    /// XML forbids these characters outright, and the renderer used to copy them into the
    /// document raw (#80). A SwiftPM target name reaches the component box this way.
    @Test(
        "a forbidden character in any text slot is replaced, leaving the document well-formed",
        arguments: WellFormedXML.forbiddenCharacterLabels
    )
    func forbiddenCharacterInEveryTextSlotIsReplaced(label: String) {
        let model = ComponentModel(
            components: [
                Component(name: "App", kind: .executable),
                Component(name: label, kind: .library, providedInterfaces: [label])
            ],
            dependencies: [ComponentDependency(from: "App", to: label)]
        )
        let svg = ComponentSVGRenderer.render(model).svg

        #expect(WellFormedXML.error(in: svg) == nil)
        // The component's name and its provided interface.
        #expect(svg.ranges(of: ">\(label.xmlEscaped)</text>").count == 2)
    }
}
