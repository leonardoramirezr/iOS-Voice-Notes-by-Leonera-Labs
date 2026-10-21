import Foundation

/// Notifications from the sync engine, always delivered on the main thread.
public enum SyncEvent {
    case didLogin
    case didLogout
    /// The server rejected the session token; the user has to log in again.
    case authenticationFailed
    case failure(Error)
    /// Remote changes are about to be applied to these note keys.
    case willChangeNotes(Set<String>)
    case didChangeNote(key: String, change: NoteChange)
    case indexingStarted
    case indexingFinished
}

public enum NoteChange: Equatable {
    case insert
    case update(memberNames: [String])
    case delete
    case acknowledge
}
