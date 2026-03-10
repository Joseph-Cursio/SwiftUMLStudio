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
    private class PersistenceController_Helper {}

    static let shared = PersistenceController()

    static let managedObjectModel: NSManagedObjectModel = {
        let modelName = "SwiftPlantUMLstudio"
        let bundleID = "name.JosephCursio.SwiftPlantUMLstudio"
        
        var model: NSManagedObjectModel?
        
        // 1. Try by bundle ID
        if let appBundle = Bundle(identifier: bundleID),
           let modelURL = appBundle.url(forResource: modelName, withExtension: "momd") {
            model = NSManagedObjectModel(contentsOf: modelURL)
        }
        
        // 2. Try bundle for helper class
        if model == nil {
            let bundle = Bundle(for: PersistenceController_Helper.self)
            if let modelURL = bundle.url(forResource: modelName, withExtension: "momd") {
                model = NSManagedObjectModel(contentsOf: modelURL)
            }
        }
        
        // 3. Try Bundle.main
        if model == nil, let modelURL = Bundle.main.url(forResource: modelName, withExtension: "momd") {
            model = NSManagedObjectModel(contentsOf: modelURL)
        }
        
        // 4. Fallback to allBundles
        if model == nil {
            for bundle in Bundle.allBundles {
                if let modelURL = bundle.url(forResource: modelName, withExtension: "momd") {
                    model = NSManagedObjectModel(contentsOf: modelURL)
                    break
                }
            }
        }

        guard let loadedModel = model else {
            fatalError("Failed to locate or load managed object model for \(modelName) in any bundle.")
        }
        return loadedModel
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        let modelName = "SwiftPlantUMLstudio"
        container = NSPersistentContainer(name: modelName, managedObjectModel: Self.managedObjectModel)
        
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
