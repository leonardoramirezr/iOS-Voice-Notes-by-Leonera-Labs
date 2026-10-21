import CoreData
import Simperium
import VoiceNotesCore

/// A Simplenote note, synced by Simperium as an object of the `Note` bucket.
///
/// Simperium reads and writes members through key-value coding and runs on its own queues, so this class
/// must stay free of actor isolation and Swift stored properties.
@objc(Note)
public class Note: SPManagedObject {
    @NSManaged public var content: String?
    @NSManaged public var creationDate: Date?
    @NSManaged public var modificationDate: Date?
    @NSManaged public var owner: String?
    @NSManaged public var publishURL: String?
    @NSManaged public var shareURL: String?
    @NSManaged public var systemTags: String?
    @NSManaged public var tags: String?

    public override func awakeFromInsert() {
        super.awakeFromInsert()
        // Synced members must never be nil: a nil value next to a server value is sent as a removal.
        let now = Date()
        setPrimitiveValue("", forKey: NotesModel.Attribute.content)
        setPrimitiveValue("", forKey: NotesModel.Attribute.publishURL)
        setPrimitiveValue("", forKey: NotesModel.Attribute.shareURL)
        setPrimitiveValue(SystemTags.emptyList, forKey: NotesModel.Attribute.tags)
        setPrimitiveValue(SystemTags.emptyList, forKey: NotesModel.Attribute.systemTags)
        setPrimitiveValue(now, forKey: NotesModel.Attribute.creationDate)
        setPrimitiveValue(now, forKey: NotesModel.Attribute.modificationDate)
        setPrimitiveValue(NSNumber(value: false), forKey: NotesModel.Attribute.deleted)
    }

    // MARK: - The `deleted` member

    // NSManagedObject already declares a `deleted` property (getter `isDeleted`) that reports whether the
    // object was deleted from its context. Key-value coding would fall back to that getter for the key
    // "deleted", so the Simplenote "trashed" flag gets explicit Objective-C accessors.

    @objc(deleted)
    public func deletedValue() -> NSNumber? {
        willAccessValue(forKey: NotesModel.Attribute.deleted)
        defer { didAccessValue(forKey: NotesModel.Attribute.deleted) }
        return (primitiveValue(forKey: NotesModel.Attribute.deleted) as? NSNumber) ?? NSNumber(value: false)
    }

    @objc(setDeleted:)
    public func setDeletedValue(_ value: NSNumber?) {
        willChangeValue(forKey: NotesModel.Attribute.deleted)
        defer { didChangeValue(forKey: NotesModel.Attribute.deleted) }
        setPrimitiveValue(value ?? NSNumber(value: false), forKey: NotesModel.Attribute.deleted)
    }

    /// Whether the note is in the Simplenote trash.
    public var isTrashed: Bool {
        get { deletedValue()?.boolValue ?? false }
        set { setDeletedValue(NSNumber(value: newValue)) }
    }

    // MARK: - Derived values

    public var isPinned: Bool {
        SystemTags.contains(SystemTags.pinned, in: systemTags)
    }

    public var title: String {
        NoteText.title(of: content ?? "")
    }

    public var preview: String {
        NoteText.preview(of: content ?? "", limit: 200)
    }
}
