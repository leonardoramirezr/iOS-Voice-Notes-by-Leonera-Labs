import Foundation
import Observation
import VoiceNotesCore
import VoiceNotesSync

/// Editing state of one note, saved the way the official app does: 2 s after typing stops and at least every
/// 21 s while typing.
@MainActor
@Observable
final class NoteEditorModel {
    static let saveDelay: Duration = .seconds(2)
    static let guaranteedSaveDelay: Duration = .seconds(21)

    var text: String
    private(set) var note: Note?
    private let engine: SyncEngine
    private var isDirty = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var guaranteedSaveTask: Task<Void, Never>?

    init(note: Note?, engine: SyncEngine) {
        self.note = note
        self.engine = engine
        text = note?.content ?? ""
    }

    var title: String {
        let title = NoteText.title(of: text)
        if !title.isEmpty {
            return title
        }
        return note == nil ? L10n.editorNewNote : L10n.notesUntitled
    }

    var isPinned: Bool {
        note?.isPinned ?? false
    }

    func textDidChange() {
        guard text != (note?.content ?? "") else {
            return
        }
        isDirty = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else {
                return
            }
            self?.save()
        }
        if guaranteedSaveTask == nil {
            guaranteedSaveTask = Task { [weak self] in
                try? await Task.sleep(for: Self.guaranteedSaveDelay)
                guard !Task.isCancelled else {
                    return
                }
                self?.save()
            }
        }
    }

    /// Saves pending edits locally and sends them to Simplenote. A new note is created on its first save,
    /// so abandoned empty notes are never stored.
    func save() {
        saveTask?.cancel()
        saveTask = nil
        guaranteedSaveTask?.cancel()
        guaranteedSaveTask = nil
        guard isDirty else {
            return
        }
        isDirty = false
        if let note {
            engine.store.update(note, content: text)
        } else {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            note = engine.store.insertNote(content: text)
        }
        engine.save()
    }

    func togglePinned() {
        guard let note else {
            return
        }
        save()
        engine.store.setPinned(note, !note.isPinned)
        engine.save()
    }

    func moveToTrash() {
        guard let note else {
            return
        }
        save()
        engine.store.setTrashed(note, true)
        engine.save()
    }

    // MARK: - Remote changes

    /// Remote changes are about to be applied: keep unsaved text in Core Data (without sending it yet) so
    /// Simperium merges it with the incoming change instead of overwriting it.
    func remoteChangesWillApply(_ notification: Notification) {
        guard isDirty, let note, let key = note.simperiumKey,
              let keys = notification.userInfo?[RemoteChange.keys] as? Set<String>, keys.contains(key) else {
            return
        }
        note.content = text
        note.modificationDate = Date()
        engine.saveWithoutSyncing()
    }

    /// A remote change was applied. Returns true when the note was deleted or trashed and the editor should close.
    func remoteChangeDidApply(_ notification: Notification) -> Bool {
        guard let note, let key = note.simperiumKey,
              notification.userInfo?[RemoteChange.key] as? String == key else {
            return false
        }
        if (notification.userInfo?[RemoteChange.deleted] as? Bool) == true || note.isDeleted || note.isTrashed {
            return true
        }
        let remote = note.content ?? ""
        if remote != text {
            text = remote
        }
        return false
    }
}
