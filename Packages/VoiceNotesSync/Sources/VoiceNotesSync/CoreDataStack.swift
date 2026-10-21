import CoreData

/// The persistent store and main context handed to Simperium.
///
/// Simperium requires a main-queue context without a coordinator: it creates a private writer context that
/// owns the coordinator and makes the main context its child.
public final class CoreDataStack {
    public let model: NSManagedObjectModel
    public let coordinator: NSPersistentStoreCoordinator
    public let mainContext: NSManagedObjectContext
    /// True when an existing store could not be opened with the current model and was recreated empty.
    public let storeWasRecreated: Bool

    /// Opens (or creates) the SQLite store at `storeURL`, or an in-memory store when it is nil.
    public init(storeURL: URL?, model: NSManagedObjectModel = NotesModel.shared) throws {
        self.model = model
        coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        var recreated = false
        if let storeURL {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            if Self.storeIsIncompatible(at: storeURL, model: model) {
                try coordinator.destroyPersistentStore(at: storeURL, ofType: NSSQLiteStoreType, options: nil)
                recreated = true
            }
            let options: [AnyHashable: Any] = [
                NSMigratePersistentStoresAutomaticallyOption: true,
                NSInferMappingModelAutomaticallyOption: true,
            ]
            try coordinator.addPersistentStore(
                ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: options
            )
        } else {
            try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil, options: nil)
        }
        storeWasRecreated = recreated
        mainContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        mainContext.undoManager = nil
    }

    /// The default store location inside Application Support.
    public static func defaultStoreURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return support.appendingPathComponent("VoiceNotes", isDirectory: true).appendingPathComponent("Notes.sqlite")
    }

    static func storeIsIncompatible(at url: URL, model: NSManagedObjectModel) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }
        guard let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType, at: url, options: nil
        ) else {
            return true
        }
        return !model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata)
    }
}
