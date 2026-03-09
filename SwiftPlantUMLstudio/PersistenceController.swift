//
//  PersistenceController.swift
//  SwiftPlantUMLstudio
//
//  Created by Gemini on 3/7/26.
//

import CoreData

/// A modern Core Data stack manager.
@MainActor
struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "SwiftPlantUMLstudio")
        
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else {
            // Enable persistent history tracking only for on-disk stores.
            // Setting these options on an in-memory store can trigger an internal
            // dispatch_sync to the main queue, deadlocking when init runs on @MainActor.
            let description = container.persistentStoreDescriptions.first
            description?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        // Use modern initializer for concurrency safety
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    }
}
