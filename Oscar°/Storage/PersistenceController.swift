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
    
    nonisolated(unsafe) static var loadErrorNote: String?
    private static let lock = NSLock()

    let container: NSPersistentContainer
    let url: URL

    init() {
        let container = NSPersistentContainer(name: "DataModels")
        let url = URL.storeURL(for: AppGroup.identifier, dbName: "DataModels")
        container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: url)]
        container.viewContext.automaticallyMergesChangesFromParent = true
        self.container = container
        self.url = url
        load()
    }

    var isLoaded: Bool {
        !container.persistentStoreCoordinator.persistentStores.isEmpty
    }

    var isFileReadable: Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 1))?.count == 1
    }

    @discardableResult
    func load() -> Bool {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        if isLoaded { return true }
        var error = loadStore()
        if let first = error, first.code == NSPersistentStoreIncompatibleVersionHashError, canMoveAside(first) {
            Thread.sleep(forTimeInterval: 1)
            error = loadStore()
        }
        if let failed = error, canMoveAside(failed) {
            Self.moveAside(storeAt: url)
            error = loadStore()
        }
        guard let error else { return true }
        let sqlite = error.userInfo[NSSQLiteErrorDomain].map { "\($0)" } ?? "-"
        let note = "\(error.domain) \(error.code) sqlite \(sqlite)\n\(error.userInfo)"
        Self.logger.fault("Persistent store load failed: \(note, privacy: .public)")
        guard Self.isAppProcess else {
            fatalError("Unresolved error \(error), \(error.userInfo)")
        }
        if Self.loadErrorNote == nil {
            Self.loadErrorNote = note
        }
        return false
    }

    private func loadStore() -> NSError? {
        var loadError: NSError?
        container.loadPersistentStores { _, error in
            loadError = error as NSError?
        }
        return loadError
    }

    private func canMoveAside(_ error: NSError) -> Bool {
        Self.isAppProcess && Self.isUnrecoverable(error) && isFileReadable
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
