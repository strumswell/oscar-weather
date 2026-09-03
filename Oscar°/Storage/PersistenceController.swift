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
        let container = NSPersistentContainer(name: "DataModels")
        let url = inMemory
            ? URL(fileURLWithPath: "/dev/null")
            : URL.storeURL(for: AppGroup.identifier, dbName: "DataModels")
        container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: url)]

        container.loadPersistentStores { _, error in
            guard let error = error as NSError? else { return }
            Self.logger.fault(
                "Persistent store load failed: \(error.localizedDescription, privacy: .public)"
            )
            // Only the app starts over, and only for a store that can never open again
            // (corruption, downgrade past a model change). A transient failure, such as
            // an extension reading the protected file before first unlock, must not
            // rename the user's data away.
            guard !inMemory, Self.isAppProcess, Self.isUnrecoverable(error) else {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
            Self.moveAside(storeAt: url)
            container.loadPersistentStores { _, retryError in
                if let retryError = retryError as NSError? {
                    fatalError("Unresolved error \(retryError), \(retryError.userInfo)")
                }
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        self.container = container
    }

    private static var isAppProcess: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private static func isUnrecoverable(_ error: NSError) -> Bool {
        guard error.domain == NSCocoaErrorDomain else { return false }
        switch error.code {
        case NSPersistentStoreIncompatibleVersionHashError,
             NSPersistentStoreIncompatibleSchemaError,
             NSMigrationMissingSourceModelError,
             NSMigrationError,
             NSFileReadCorruptFileError:
            return true
        case NSSQLiteError:
            let sqliteCode = (error.userInfo[NSSQLiteErrorDomain] as? Int) ?? 0
            return sqliteCode == 11 || sqliteCode == 26 // SQLITE_CORRUPT, SQLITE_NOTADB
        default:
            return false
        }
    }

    private static func moveAside(storeAt url: URL) {
        let stamp = Int(Date().timeIntervalSince1970)
        for suffix in ["", "-wal", "-shm"] {
            let file = URL(fileURLWithPath: url.path + suffix)
            try? FileManager.default.moveItem(
                at: file, to: URL(fileURLWithPath: url.path + suffix + ".corrupt-\(stamp)"))
        }
    }
}

extension URL {
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
