import CoreData

/// The Core Data model synced with the Simplenote backend.
///
/// Simperium uses the entity name as the bucket name, so the entity must be called `Note`. The attributes
/// mirror the members of a Simplenote note; `simperiumKey` and `ghostData` are Simperium's bookkeeping and
/// are never synced. Built in code so it can be shared by the app and the tests without a compiled model.
public enum NotesModel {
    public static let entityName = "Note"

    public enum Attribute {
        public static let simperiumKey = "simperiumKey"
        public static let ghostData = "ghostData"
        public static let content = "content"
        public static let creationDate = "creationDate"
        public static let modificationDate = "modificationDate"
        public static let deleted = "deleted"
        public static let owner = "owner"
        public static let publishURL = "publishURL"
        public static let shareURL = "shareURL"
        public static let systemTags = "systemTags"
        public static let tags = "tags"
    }

    /// Simperium reads this userInfo key to override the member type of an attribute.
    static let memberTypeKey = "spOverride"
    static let jsonListType = "jsonlist"

    /// Built once: Core Data requires a single model instance per entity class in a process.
    public static let shared: NSManagedObjectModel = makeModel()

    static func makeModel() -> NSManagedObjectModel {
        let simperiumKey = attribute(Attribute.simperiumKey, .stringAttributeType)
        let entity = NSEntityDescription()
        entity.name = entityName
        entity.managedObjectClassName = NSStringFromClass(Note.self)
        entity.properties = [
            simperiumKey,
            attribute(Attribute.ghostData, .stringAttributeType),
            attribute(Attribute.content, .stringAttributeType),
            attribute(Attribute.creationDate, .dateAttributeType),
            attribute(Attribute.modificationDate, .dateAttributeType),
            attribute(Attribute.deleted, .booleanAttributeType, optional: false, defaultValue: false),
            attribute(Attribute.owner, .stringAttributeType),
            attribute(Attribute.publishURL, .stringAttributeType),
            attribute(Attribute.shareURL, .stringAttributeType),
            attribute(Attribute.systemTags, .stringAttributeType, userInfo: [memberTypeKey: jsonListType]),
            attribute(Attribute.tags, .stringAttributeType, userInfo: [memberTypeKey: jsonListType]),
        ]
        entity.indexes = [
            NSFetchIndexDescription(
                name: "bySimperiumKey",
                elements: [NSFetchIndexElementDescription(property: simperiumKey, collationType: .binary)]
            ),
        ]
        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        optional: Bool = true,
        defaultValue: Any? = nil,
        userInfo: [AnyHashable: Any] = [:]
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        attribute.defaultValue = defaultValue
        attribute.userInfo = userInfo
        return attribute
    }
}
