//
//  DiagramEntity.swift
//  SwiftPlantUMLstudio
//
//  Created by Gemini on 3/7/26.
//

import Foundation
import CoreData

@objc(DiagramEntity)
public class DiagramEntity: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var mode: String?
    @NSManaged public var format: String?
    @NSManaged public var entryPoint: String?
    @NSManaged public var sequenceDepth: Int16
    @NSManaged public var paths: Data?
    @NSManaged public var scriptText: String?
    @NSManaged public var timestamp: Date?
    @NSManaged public var name: String?
}

extension DiagramEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<DiagramEntity> {
        return NSFetchRequest<DiagramEntity>(entityName: "DiagramEntity")
    }
}
