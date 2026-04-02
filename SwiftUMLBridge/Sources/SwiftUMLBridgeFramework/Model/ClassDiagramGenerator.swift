import Foundation

/// UML Class Diagram powered by PlantUML
public struct ClassDiagramGenerator {
    private let fileCollector = FileCollector()

    public init() {}

    /// Generate diagram from Swift file(s)
    public func generate(
        for paths: [String],
        with configuration: Configuration = .default,
        presentedBy presenter: DiagramPresenting = BrowserPresenter(),
        sdkPath: String? = nil
    ) async {
        let startDate = Date()
        let files = fileCollector.getFiles(for: paths)
        let script = generateScript(for: files, with: configuration, sdkPath: sdkPath)
        logProcessingDuration(started: startDate)
        await presenter.present(script: script)
    }

    /// Generate diagram from Swift source string
    public func generate(
        from content: String,
        with configuration: Configuration = .default,
        presentedBy presenter: DiagramPresenting = BrowserPresenter()
    ) async {
        let startDate = Date()
        let script = generateScript(for: content, with: configuration)
        logProcessingDuration(started: startDate)
        await presenter.present(script: script)
    }

    func generateScript(for content: String, with configuration: Configuration = .default) -> DiagramScript {
        var allValidItems: [SyntaxStructure] = []
        if let validItems = SyntaxStructure.create(from: content)?.substructure {
            allValidItems.append(contentsOf: validItems)
        }
        return DiagramScript(items: allValidItems, configuration: configuration)
    }

    func generateScript(
        for files: [URL],
        with configuration: Configuration = .default,
        sdkPath: String? = nil
    ) -> DiagramScript {
        var allValidItems: [SyntaxStructure] = []
        for aFile in files {
            if let validItems = SyntaxStructure.create(from: aFile, sdkPath: sdkPath)?.substructure {
                allValidItems.append(contentsOf: validItems)
            }
        }
        return DiagramScript(items: allValidItems, configuration: configuration)
    }

    /// Generate a DiagramScript from paths — synchronous entry point for GUI integration.
    public func generateScript(
        for paths: [String],
        with configuration: Configuration = .default,
        sdkPath: String? = nil
    ) -> DiagramScript {
        let files = fileCollector.getFiles(for: paths)
        return generateScript(for: files, with: configuration, sdkPath: sdkPath)
    }

    /// Analyze types in the given paths without generating diagram output.
    /// Returns lightweight TypeInfo structs for project-level analysis.
    public func analyzeTypes(
        for paths: [String],
        sdkPath: String? = nil
    ) -> [TypeInfo] {
        let files = fileCollector.getFiles(for: paths)
        var allItems: [SyntaxStructure] = []
        for aFile in files {
            if let validItems = SyntaxStructure.create(from: aFile, sdkPath: sdkPath)?.substructure {
                allItems.append(contentsOf: validItems)
            }
        }
        return allItems.compactMap { TypeInfo(from: $0) }
    }

    func logProcessingDuration(started processingStartDate: Date) {
        let elapsed = Date().timeIntervalSince(processingStartDate)
        BridgeLogger.shared.info("Class diagram generated in \(elapsed) seconds and will be presented now")
    }
}
