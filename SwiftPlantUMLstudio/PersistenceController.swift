import Foundation
import SwiftData

/// Manages the SwiftData model container for the app.
@MainActor
struct PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer

    init(inMemory: Bool = false) {
        let schema = Schema([DiagramEntity.self, ProjectSnapshot.self])
        let config = ModelConfiguration(
            "SwiftPlantUMLstudio",
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
