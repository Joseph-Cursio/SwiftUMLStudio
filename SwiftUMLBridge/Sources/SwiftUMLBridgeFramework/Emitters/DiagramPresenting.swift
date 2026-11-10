/// Unified interface for presenting a diagram script
public protocol DiagramPresenting: Sendable {
    /// Present script/diagram to user
    /// - Parameter script: any DiagramOutputting (PlantUML or Mermaid, class or sequence)
    func present(script: any DiagramOutputting) async
}
