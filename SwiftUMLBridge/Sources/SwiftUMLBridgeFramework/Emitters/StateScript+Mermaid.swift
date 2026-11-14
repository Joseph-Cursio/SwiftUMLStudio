// MARK: - Mermaid

extension StateScript {
    static func buildMermaidText(model: StateMachineModel) -> String {
        var lines = ["stateDiagram-v2", "%% title: \(model.hostType).\(model.enumType)"]
        lines += transitionLines(model: model)
        return lines.joined(separator: "\n")
    }
}
