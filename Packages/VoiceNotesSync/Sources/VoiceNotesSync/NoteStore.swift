import CoreData
import VoiceNotesCore

/// Queries and edits notes in the main context. Call `SyncEngine.save()` afterwards to persist and sync.
public final class NoteStore {
    public let context: NSManagedObjectContext

    public init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Predicates

    private static let pinnedToken = "\"\(SystemTags.pinned)\""

    /// Notes that are not in the trash (`deleted` may be NULL for objects that never set it).
    public static var activePredicate: NSPredicate {
        NSPredicate(format: "%K == NO OR %K == nil", NotesModel.Attribute.deleted, NotesModel.Attribute.deleted)
    }

    public static func listPredicate(pinned: Bool, search: String = "") -> NSPredicate {
        let pinnedPredicate = pinned
            ? NSPredicate(format: "%K CONTAINS %@", NotesModel.Attribute.systemTags, pinnedToken)
            : NSPredicate(
                format: "%K == nil OR NOT (%K CONTAINS %@)",
                NotesModel.Attribute.systemTags, NotesModel.Attribute.systemTags, pinnedToken
            )
        var predicates = [activePredicate, pinnedPredicate]
        if let searchPredicate = searchPredicate(search) {
            predicates.append(searchPredicate)
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    /// Every whitespace-separated word must appear in the content (case and diacritics are ignored).
    public static func searchPredicate(_ query: String) -> NSPredicate? {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else {
            return nil
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: words.map {
            NSPredicate(format: "%K CONTAINS[cd] %@", NotesModel.Attribute.content, $0)
        })
    }

    public static var sortDescriptors: [NSSortDescriptor] {
        [NSSortDescriptor(key: NotesModel.Attribute.modificationDate, ascending: false)]
    }

    public static func listFetchRequest(pinned: Bool, search: String = "") -> NSFetchRequest<Note> {
        let request = NSFetchRequest<Note>(entityName: NotesModel.entityName)
        request.predicate = listPredicate(pinned: pinned, search: search)
        request.sortDescriptors = sortDescriptors
        request.fetchBatchSize = 50
        return request
    }

    // MARK: - Queries

    /// Active notes, pinned first, most recently modified first.
    public func activeNotes(limit: Int? = nil) -> [Note] {
        let request = NSFetchRequest<Note>(entityName: NotesModel.entityName)
        request.predicate = Self.activePredicate
        request.sortDescriptors = Self.sortDescriptors
        let notes = (try? context.fetch(request)) ?? []
        let ordered = notes.filter(\.isPinned) + notes.filter { !$0.isPinned }
        guard let limit else {
            return ordered
        }
        return Array(ordered.prefix(limit))
    }

    public func note(withKey key: String) -> Note? {
        let request = NSFetchRequest<Note>(entityName: NotesModel.entityName)
        request.predicate = NSPredicate(format: "%K == %@", NotesModel.Attribute.simperiumKey, key)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    // MARK: - Changes

    @discardableResult
    public func insertNote(content: String, date: Date = Date()) -> Note {
        let object = NSEntityDescription.insertNewObject(forEntityName: NotesModel.entityName, into: context)
        guard let note = object as? Note else {
            fatalError("The Note entity must use the Note class")
        }
        note.content = content
        note.creationDate = date
        note.modificationDate = date
        return note
    }

    public func update(_ note: Note, content: String, date: Date = Date()) {
        guard note.content != content else {
            return
        }
        note.content = content
        note.modificationDate = date
    }

    public func setTrashed(_ note: Note, _ trashed: Bool, date: Date = Date()) {
        note.isTrashed = trashed
        note.modificationDate = date
    }

    public func setPinned(_ note: Note, _ pinned: Bool, date: Date = Date()) {
        note.systemTags = SystemTags.setting(SystemTags.pinned, pinned, in: note.systemTags)
        note.modificationDate = date
    }

    /// Removes a note that was never saved (an empty note the user abandoned).
    public func discard(_ note: Note) {
        context.delete(note)
    }
}
