import CoreData
import Simperium
import VoiceNotesCore
import XCTest
@testable import VoiceNotesSync

/// Verifies that the Swift `Note` class behaves like the official Objective-C model when Simperium reads and
/// writes it through key-value coding.
final class NoteInteropTests: XCTestCase {
    private var engine: SyncEngine!

    override func setUpWithError() throws {
        engine = try SyncEngine(storeURL: nil, label: "tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        engine = nil
    }

    func testEntityUsesTheNoteClass() throws {
        let entity = try XCTUnwrap(NotesModel.shared.entitiesByName[NotesModel.entityName])
        XCTAssertEqual(entity.managedObjectClassName, "Note")
        XCTAssertTrue(NSClassFromString("Note") == Note.self)
        XCTAssertNotNil(engine.notesBucket)
    }

    func testNewNoteHasNonNilSyncedMembers() {
        let note = engine.store.insertNote(content: "Title\nBody")
        XCTAssertEqual(note.publishURL, "")
        XCTAssertEqual(note.shareURL, "")
        XCTAssertEqual(note.tags, "[]")
        XCTAssertEqual(note.systemTags, "[]")
        XCTAssertNotNil(note.creationDate)
        XCTAssertFalse(note.isTrashed)
    }

    func testSimperiumDictionaryContainsTheSyncedMembers() throws {
        let note = engine.store.insertNote(content: "Title\nBody")
        engine.context.processPendingChanges()
        XCTAssertNotNil(note.simperiumKey)
        let dictionary = try XCTUnwrap(note.value(forKey: "dictionary") as? [String: Any])
        for key in ["content", "creationDate", "modificationDate", "deleted", "publishURL", "shareURL", "systemTags", "tags"] {
            XCTAssertNotNil(dictionary[key], "missing member \(key)")
        }
        XCTAssertNil(dictionary["simperiumKey"])
        XCTAssertNil(dictionary["ghostData"])
        XCTAssertEqual(dictionary["content"] as? String, "Title\nBody")
        XCTAssertEqual(dictionary["systemTags"] as? [String], [])
        XCTAssertEqual((dictionary["deleted"] as? NSNumber)?.boolValue, false)
        XCTAssertTrue(dictionary["creationDate"] is NSNumber)
    }

    func testRemoteMemberDataIsAppliedThroughKeyValueCoding() throws {
        let note = engine.store.insertNote(content: "Old")
        engine.context.processPendingChanges()
        note.loadMemberData([
            "content": "Remote",
            "deleted": true,
            "systemTags": ["pinned", "markdown"],
            "modificationDate": 1_700_000_000.5,
        ])
        XCTAssertEqual(note.content, "Remote")
        XCTAssertTrue(note.isTrashed)
        XCTAssertFalse(note.isDeleted, "the Core Data deletion flag must not change")
        XCTAssertTrue(note.isPinned)
        XCTAssertEqual(SystemTags.decode(note.systemTags), ["pinned", "markdown"])
        XCTAssertEqual(try XCTUnwrap(note.modificationDate).timeIntervalSince1970, 1_700_000_000.5, accuracy: 0.001)
        XCTAssertFalse(NoteStore.activePredicate.evaluate(with: note))
    }

    func testDeletedKeyValueCoding() {
        let note = engine.store.insertNote(content: "Note")
        XCTAssertEqual((note.value(forKey: "deleted") as? NSNumber)?.boolValue, false)
        note.setValue(true, forKey: "deleted")
        XCTAssertTrue(note.isTrashed)
        note.setValue(nil, forKey: "deleted")
        XCTAssertFalse(note.isTrashed)
        XCTAssertTrue(NoteStore.activePredicate.evaluate(with: note))
    }

    func testPinnedPredicatesInMemory() {
        let pinned = engine.store.insertNote(content: "Pinned")
        engine.store.setPinned(pinned, true)
        let plain = engine.store.insertNote(content: "Plain")
        let missing = engine.store.insertNote(content: "No tags")
        missing.systemTags = nil
        XCTAssertTrue(NoteStore.listPredicate(pinned: true).evaluate(with: pinned))
        XCTAssertFalse(NoteStore.listPredicate(pinned: false).evaluate(with: pinned))
        XCTAssertTrue(NoteStore.listPredicate(pinned: false).evaluate(with: plain))
        XCTAssertTrue(NoteStore.listPredicate(pinned: false).evaluate(with: missing))
    }

    func testDelegateAdapterRespondsToEveryCallback() {
        let adapter = SimperiumDelegateAdapter()
        for selector in [
            "simperiumDidLogin:",
            "simperiumDidLogout:",
            "simperium:didFailWithError:",
            "bucket:willChangeObjectsForKeys:",
            "bucket:didChangeObjectForKey:forChangeType:memberNames:",
            "bucketWillStartIndexing:",
            "bucketDidFinishIndexing:",
        ] {
            XCTAssertTrue(adapter.responds(to: NSSelectorFromString(selector)), selector)
        }
    }

    func testInvalidTokenErrorIsReportedAsAuthenticationFailure() {
        let adapter = SimperiumDelegateAdapter()
        var events: [String] = []
        adapter.handler = { event in
            if case .authenticationFailed = event { events.append("auth") }
            if case .failure = event { events.append("failure") }
        }
        adapter.simperium(engine.simperium, didFailWithError: NSError(domain: "Simperium", code: 4))
        adapter.simperium(engine.simperium, didFailWithError: NSError(domain: "Other", code: 4))
        XCTAssertEqual(events, ["auth", "failure"])
    }
}

/// Runs the list predicates against a real SQLite store to check their SQL translation.
final class NotePredicateStoreTests: XCTestCase {
    func testPredicatesOnSQLite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stack = try CoreDataStack(storeURL: directory.appendingPathComponent("Notes.sqlite"))
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = stack.coordinator
        let store = NoteStore(context: context)

        let pinned = store.insertNote(content: "Pinned note")
        store.setPinned(pinned, true)
        store.insertNote(content: "Plain note")
        let untagged = store.insertNote(content: "Untagged note")
        untagged.systemTags = nil
        let trashed = store.insertNote(content: "Trashed note")
        trashed.isTrashed = true
        try context.save()
        context.reset()

        func titles(pinned: Bool, search: String = "") throws -> [String] {
            try context.fetch(NoteStore.listFetchRequest(pinned: pinned, search: search)).map(\.title).sorted()
        }
        XCTAssertEqual(try titles(pinned: true), ["Pinned note"])
        XCTAssertEqual(try titles(pinned: false), ["Plain note", "Untagged note"])
        XCTAssertEqual(try titles(pinned: false, search: "UNTÁGGED"), ["Untagged note"])
        XCTAssertEqual(try titles(pinned: false, search: "note plain"), ["Plain note"])
    }

    func testIncompatibleStoreIsRecreated() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Notes.sqlite")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let otherEntity = NSEntityDescription()
        otherEntity.name = "Other"
        let attribute = NSAttributeDescription()
        attribute.name = "value"
        attribute.attributeType = .stringAttributeType
        otherEntity.properties = [attribute]
        let otherModel = NSManagedObjectModel()
        otherModel.entities = [otherEntity]
        let otherCoordinator = NSPersistentStoreCoordinator(managedObjectModel: otherModel)
        let store = try otherCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: nil)
        try otherCoordinator.remove(store)

        let stack = try CoreDataStack(storeURL: url)
        XCTAssertTrue(stack.storeWasRecreated)
        let reopened = try CoreDataStack(storeURL: url)
        XCTAssertFalse(reopened.storeWasRecreated)
    }
}
