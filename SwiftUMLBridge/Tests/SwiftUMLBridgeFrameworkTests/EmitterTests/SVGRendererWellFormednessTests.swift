import Testing
@testable import SwiftUMLBridgeFramework

/// Parses `SVGRenderer` output as XML. The other `SVGRenderer` tests check substrings, which a
/// malformed document can still contain (#56).
@Suite("SVGRenderer — well-formedness")
struct SVGRendererWellFormednessTests {

    /// Hyphenated labels. Copied into an XML comment, every one but `ends-` breaks the document,
    /// because `--` is illegal there and no escape helps (#56). `a---b` and `ends-` catch the two
    /// ways a sanitizer could still fail: one `--` replacement pass leaves `a- --b`, and a comment
    /// closed without its space turns `ends-` into `ends--->`.
    private static let hyphenatedLabels = ["Old--Code", "a---b", "ends-", "--", "-->", "Old--Code<T> & \"x\""]

    @Test("a node label containing hyphens leaves the document well-formed", arguments: hyphenatedLabels)
    func nodeLabelKeepsDocumentWellFormed(label: String) {
        var node = LayoutNode(id: "node", label: label, stereotype: "class")
        node.posX = 100; node.posY = 60; node.width = 120; node.height = 50
        let svg = SVGRenderer.render(LayoutGraph(nodes: [node]))

        #expect(WellFormedXML.error(in: svg) == nil)
        #expect(svg.contains(">\(label.xmlEscaped)</text>"))
    }

    @Test("a cluster label containing hyphens leaves the document well-formed", arguments: hyphenatedLabels)
    func clusterLabelKeepsDocumentWellFormed(label: String) {
        var cluster = LayoutCluster(id: label, label: label)
        cluster.posX = 200; cluster.posY = 150; cluster.width = 300; cluster.height = 220
        var graph = LayoutGraph()
        graph.clusters = [cluster]
        let svg = SVGRenderer.render(graph)

        #expect(WellFormedXML.error(in: svg) == nil)
        #expect(svg.contains(">\(label.xmlEscaped)</text>"))
    }

    /// XML forbids these characters outright, and the renderer used to copy them into the
    /// document raw (#80).
    @Test(
        "a forbidden character in any text slot is replaced, leaving the document well-formed",
        arguments: WellFormedXML.forbiddenCharacterLabels
    )
    func forbiddenCharacterInEveryTextSlotIsReplaced(label: String) {
        var cluster = LayoutCluster(id: "Core", label: label)
        cluster.posX = 150; cluster.posY = 120; cluster.width = 280; cluster.height = 200
        var source = LayoutNode(
            id: "source", label: label, stereotype: label, compartments: [NodeCompartment(items: [label])]
        )
        source.posX = 100; source.posY = 60; source.width = 160; source.height = 80
        var target = LayoutNode(id: "target", label: "Target", stereotype: "struct")
        target.posX = 100; target.posY = 200; target.width = 120; target.height = 50
        var edge = LayoutEdge(sourceId: "source", targetId: "target", label: label, style: .dependency)
        edge.points = [LayoutPoint(posX: 100, posY: 100), LayoutPoint(posX: 100, posY: 175)]
        var graph = LayoutGraph(nodes: [source, target], edges: [edge])
        graph.clusters = [cluster]
        let svg = SVGRenderer.render(graph)

        #expect(WellFormedXML.error(in: svg) == nil)
        // Node label, compartment item, cluster label and edge label, then the stereotype.
        #expect(svg.ranges(of: ">\(label.xmlEscaped)</text>").count == 4)
        #expect(svg.contains("&#x00AB;\(label.xmlEscaped)&#x00BB;</text>"))
    }

    @Test("a graph with clusters, nodes, compartments and labelled edges is well-formed")
    func fullGraphIsWellFormed() {
        var cluster = LayoutCluster(id: "Core", label: "Core")
        cluster.posX = 150; cluster.posY = 120; cluster.width = 280; cluster.height = 200
        var parent = LayoutNode(
            id: "parent", label: "Base", stereotype: "protocol",
            compartments: [NodeCompartment(items: ["+ run() -> Result<Int, Error>"])]
        )
        parent.posX = 100; parent.posY = 60; parent.width = 160; parent.height = 80
        var child = LayoutNode(id: "child", label: "Impl", stereotype: "struct")
        child.posX = 100; child.posY = 200; child.width = 120; child.height = 50
        var edge = LayoutEdge(sourceId: "child", targetId: "parent", label: "conforms & <is>", style: .realization)
        edge.points = [LayoutPoint(posX: 100, posY: 175), LayoutPoint(posX: 100, posY: 100)]
        var graph = LayoutGraph(nodes: [parent, child], edges: [edge])
        graph.clusters = [cluster]

        #expect(WellFormedXML.error(in: SVGRenderer.render(graph)) == nil)
    }
}
