import CoreData
import Simperium

/// Owns the Core Data stack and the Simperium instance that syncs notes with the Simplenote backend.
///
/// Use it from the main thread only. Authentication runs in Simperium's token mode: the app performs the
/// Simplenote login itself, keeps the token in the Keychain and hands it to Simperium on every launch, so the
/// library never shows its own login UI.
public final class SyncEngine {
    /// The production Simperium app of Simplenote.
    public static let simplenoteAppID = "chalk-bump-f49"

    public let appID: String
    public let stack: CoreDataStack
    public let simperium: Simperium
    public let store: NoteStore
    private let adapter = SimperiumDelegateAdapter()

    /// Receives sync events on the main thread.
    public var onEvent: ((SyncEvent) -> Void)? {
        get { adapter.handler }
        set { adapter.handler = newValue }
    }

    /// Creates the stack and Simperium. Must run before anything fetches notes.
    public init(storeURL: URL?, appID: String = SyncEngine.simplenoteAppID, label: String = "") throws {
        self.appID = appID
        stack = try CoreDataStack(storeURL: storeURL)
        simperium = Simperium(
            model: stack.model,
            context: stack.mainContext,
            coordinator: stack.coordinator,
            label: label,
            bucketOverrides: nil
        )
        simperium.verboseLoggingEnabled = false
        if stack.storeWasRecreated {
            // The local database is new: forget sync markers and ghosts so everything is downloaded again.
            simperium.resetMetadata()
        }
        simperium.delegate = adapter
        notesBucket?.delegate = adapter
        store = NoteStore(context: stack.mainContext)
    }

    /// The main-queue context to use for the UI and for every local change.
    public var context: NSManagedObjectContext {
        stack.mainContext
    }

    public var notesBucket: SPBucket? {
        simperium.bucket(forName: NotesModel.entityName)
    }

    /// Starts syncing with a Simplenote sync token.
    public func start(token: String) {
        simperium.authenticate(withAppID: appID, token: token)
    }

    /// Saves local changes and sends them to the server.
    public func save() {
        simperium.save()
    }

    /// Saves local changes without sending them (used right before remote changes are applied).
    public func saveWithoutSyncing() {
        simperium.saveWithoutSyncing()
    }

    /// Number of local changes that were not acknowledged by the server yet.
    public func pendingChangeCount(completion: @escaping (Int) -> Void) {
        guard let bucket = notesBucket else {
            completion(0)
            return
        }
        bucket.stats { _, pending, enqueued, deletions in
            completion(Int(pending + enqueued + deletions))
        }
    }

    /// Stops syncing, forgets the session and deletes every local note.
    public func signOut(completion: @escaping () -> Void) {
        simperium.signOutAndRemoveLocalData(true) {
            completion()
        }
    }
}
