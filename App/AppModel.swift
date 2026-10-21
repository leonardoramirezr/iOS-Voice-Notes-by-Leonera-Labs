import CoreData
import Foundation
import Observation
import VoiceNotesCore
import VoiceNotesSync

extension Notification.Name {
    /// Remote changes are about to be applied; `userInfo[RemoteChange.keys]` holds the note keys.
    static let notesWillChangeRemotely = Notification.Name("VoiceNotes.notesWillChangeRemotely")
    /// A remote change was applied; `userInfo` holds `RemoteChange.key` and `RemoteChange.deleted`.
    static let noteDidChangeRemotely = Notification.Name("VoiceNotes.noteDidChangeRemotely")
}

enum RemoteChange {
    static let keys = "keys"
    static let key = "key"
    static let deleted = "deleted"
}

enum NoteSaveError: Error {
    case noteMissing(String)
}

/// Application state shared by every screen: session, sync engine and settings.
@MainActor
@Observable
final class AppModel {
    enum Route: Equatable {
        case loggedOut
        case sessionExpired(email: String)
        case ready
        case signingOut
        case failed(String)
    }

    private(set) var route: Route
    private(set) var account: String?
    private(set) var isIndexing = false
    let settings = AppSettings()
    let engine: SyncEngine?
    private let credentials = CredentialsStore()

    init() {
        let engine: SyncEngine
        do {
            // Simperium must exist before anything fetches notes.
            engine = try SyncEngine(storeURL: CoreDataStack.defaultStoreURL())
        } catch {
            self.engine = nil
            route = .failed(error.localizedDescription)
            return
        }
        self.engine = engine
        let saved = credentials.load()
        account = saved?.username
        route = saved == nil ? .loggedOut : .ready
        engine.onEvent = { [weak self] event in
            // Simperium calls its delegates on the main thread; hop there if that ever changes.
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.handle(event)
                }
            } else {
                Task { @MainActor in
                    self?.handle(event)
                }
            }
        }
        if let saved {
            engine.start(token: saved.token)
        }
    }

    // MARK: - Session

    func didLogIn(_ login: SimplenoteLogin) async {
        guard let engine else {
            return
        }
        if let previous = account, previous.caseInsensitiveCompare(login.username) != .orderedSame {
            // Another account logged in after the session expired: never mix its notes with the old ones.
            await withCheckedContinuation { continuation in
                engine.signOut { continuation.resume() }
            }
        }
        try? credentials.save(Credentials(username: login.username, token: login.syncToken))
        account = login.username
        route = .ready
        engine.start(token: login.syncToken)
    }

    /// Changes that were not acknowledged by the server yet (lost on sign out).
    func pendingChangeCount() async -> Int {
        guard let engine else {
            return 0
        }
        return await withCheckedContinuation { continuation in
            engine.pendingChangeCount { continuation.resume(returning: $0) }
        }
    }

    func signOut() async {
        guard let engine else {
            return
        }
        route = .signingOut
        await withCheckedContinuation { continuation in
            engine.signOut { continuation.resume() }
        }
        credentials.delete()
        account = nil
        isIndexing = false
        route = .loggedOut
    }

    func saveAll() {
        engine?.save()
    }

    // MARK: - Notes for voice commands

    /// Active notes as plain values for the voice pipeline (notes without a key yet are skipped).
    func noteRecords() -> [NoteRecord] {
        (engine?.store.activeNotes() ?? []).compactMap(Self.record(of:))
    }

    /// The active note with this key as a plain value, or nil when it was deleted or trashed.
    func noteRecord(withKey key: String) -> NoteRecord? {
        guard let note = engine?.store.note(withKey: key), !note.isTrashed, !note.isDeleted else {
            return nil
        }
        return Self.record(of: note)
    }

    /// The note as a plain value, or nil when Simperium did not give it a key yet.
    static func record(of note: Note) -> NoteRecord? {
        guard let key = note.simperiumKey, !key.isEmpty else {
            return nil
        }
        return NoteRecord(
            key: key,
            title: note.title,
            content: note.content ?? "",
            modificationDate: note.modificationDate ?? .distantPast
        )
    }

    /// Saves reviewed voice changes locally and sends them to Simplenote. Edits are applied again to the
    /// current text, so changes that arrived from other devices while reviewing are kept.
    func save(_ changes: [ProposedChange]) throws {
        guard let engine else {
            return
        }
        let store = engine.store
        for change in changes {
            switch change.target {
            case .new(let title):
                if let existing = PlanValidator.existingNote(titled: title, in: noteRecords()),
                   let note = store.note(withKey: existing.key) {
                    // A note with this title appeared meanwhile: add to it instead of creating a duplicate.
                    guard !change.edits.isEmpty else {
                        continue
                    }
                    let result = try EditApplier.apply(change.edits, to: note.content ?? "")
                    store.update(note, content: result.newContent)
                } else {
                    store.insertNote(content: change.result.newContent)
                }
            case .existing(let key):
                guard let note = store.note(withKey: key), !note.isTrashed else {
                    throw NoteSaveError.noteMissing(change.title)
                }
                let result = try change.reapplied(toCurrentContent: note.content ?? "")
                store.update(note, content: result.newContent)
            }
        }
        engine.save()
    }

    // MARK: - Sync events

    private func handle(_ event: SyncEvent) {
        switch event {
        case .authenticationFailed:
            if route == .ready {
                route = .sessionExpired(email: account ?? "")
            }
        case .indexingStarted:
            isIndexing = true
        case .indexingFinished:
            isIndexing = false
        case .willChangeNotes(let keys):
            NotificationCenter.default.post(
                name: .notesWillChangeRemotely, object: nil, userInfo: [RemoteChange.keys: keys]
            )
        case .didChangeNote(let key, let change):
            NotificationCenter.default.post(
                name: .noteDidChangeRemotely,
                object: nil,
                userInfo: [RemoteChange.key: key, RemoteChange.deleted: change == .delete]
            )
        case .didLogin, .didLogout, .failure:
            break
        }
    }
}
