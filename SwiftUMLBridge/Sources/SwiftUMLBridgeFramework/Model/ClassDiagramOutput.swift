/// Defines how to output the generated diagram
public enum ClassDiagramOutput: String, CaseIterable, Codable {
    case browser
    case browserImageOnly
    case consoleOnly
}
