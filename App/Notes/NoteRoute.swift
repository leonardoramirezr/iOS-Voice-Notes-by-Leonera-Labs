import CoreData

/// Navigation destinations of the notes list.
enum NoteRoute: Hashable {
    case note(NSManagedObjectID)
    /// A note that is created when the user types its first character.
    case new(UUID)
}
