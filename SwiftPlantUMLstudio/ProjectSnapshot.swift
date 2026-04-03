import Foundation
import CoreData

@objc(ProjectSnapshot)
public class ProjectSnapshot: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var timestamp: Date?
    @NSManaged public var typeCount: Int32
    @NSManaged public var relationshipCount: Int32
    @NSManaged public var moduleCount: Int16
    @NSManaged public var fileCount: Int32
    @NSManaged public var typeBreakdown: Data?
    @NSManaged public var topConnectedTypes: Data?
    @NSManaged public var projectPaths: Data?
}

extension ProjectSnapshot {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ProjectSnapshot> {
        return NSFetchRequest<ProjectSnapshot>(entityName: "ProjectSnapshot")
    }

    /// Decoded type breakdown dictionary.
    var decodedTypeBreakdown: [String: Int] {
        guard let data = typeBreakdown else { return [:] }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    /// Decoded top connected types as name-count pairs.
    var decodedTopConnectedTypes: [(name: String, connectionCount: Int)] {
        guard let data = topConnectedTypes else { return [] }
        let pairs = (try? JSONDecoder().decode([[String: Int]].self, from: data)) ?? []
        return pairs.compactMap { dict in
            guard let entry = dict.first else { return nil }
            return (name: entry.key, connectionCount: entry.value)
        }
    }

    /// Decoded project paths.
    var decodedProjectPaths: [String] {
        guard let data = projectPaths else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}
