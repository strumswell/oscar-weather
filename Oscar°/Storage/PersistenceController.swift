//
//  PersistenceController.swift
//  PersistenceController
//
//  Created by Philipp Bolte on 16.08.21.
//

import CoreData
import OSLog

struct PersistenceController {
    static let shared = PersistenceController()
    fileprivate static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Oscar",
        category: "Storage"
    )
    
    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "DataModels")
        let url = URL.storeURL(for: "group.cloud.bolte.Oscar", dbName: "DataModels")
        let storeDescription = NSPersistentStoreDescription(url: url)
        container.persistentStoreDescriptions = [storeDescription]
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                Self.logger.fault(
                    "Persistent store load failed: \(error.localizedDescription, privacy: .public)"
                )
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}

public extension URL {
    static func storeURL(for appGroup: String, dbName: String) -> URL {
        guard let fileContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            PersistenceController.logger.fault(
                "Shared file container could not be created for \(appGroup, privacy: .public)"
            )
            fatalError("Shared file container could not be created.")
        }
        return fileContainer.appendingPathComponent("\(dbName).sqlite")
    }
}
