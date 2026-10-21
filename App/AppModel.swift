import Foundation
import Observation
import VoiceNotesSync

/// Application state shared by every screen.
@MainActor
@Observable
final class AppModel {
    let engine: SyncEngine?
    let startupError: String?

    init() {
        do {
            // Simperium must exist before anything fetches notes.
            engine = try SyncEngine(storeURL: CoreDataStack.defaultStoreURL())
            startupError = nil
        } catch {
            engine = nil
            startupError = error.localizedDescription
        }
    }

    var noteCount: Int {
        engine?.store.activeNotes().count ?? 0
    }
}
