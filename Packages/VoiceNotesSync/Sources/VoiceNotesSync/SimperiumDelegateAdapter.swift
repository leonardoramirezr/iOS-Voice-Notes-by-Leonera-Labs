import Foundation
import Simperium

/// Receives Simperium and bucket callbacks (always on the main thread) and forwards them as `SyncEvent`s.
///
/// The Swift signatures must match the imported Objective-C requirements exactly; otherwise the optional
/// protocol methods are silently never called.
final class SimperiumDelegateAdapter: NSObject, SimperiumDelegate, SPBucketDelegate {
    /// `SPSimperiumErrors.invalidToken`.
    static let invalidTokenErrorCode = 4
    static let errorDomain = "Simperium"

    var handler: ((SyncEvent) -> Void)?

    // MARK: SimperiumDelegate

    func simperiumDidLogin(_ simperium: Simperium) {
        handler?(.didLogin)
    }

    func simperiumDidLogout(_ simperium: Simperium) {
        handler?(.didLogout)
    }

    func simperium(_ simperium: Simperium, didFailWithError error: Error) {
        let nsError = error as NSError
        if nsError.domain == Self.errorDomain, nsError.code == Self.invalidTokenErrorCode {
            handler?(.authenticationFailed)
        } else {
            handler?(.failure(error))
        }
    }

    // MARK: SPBucketDelegate

    func bucket(_ bucket: SPBucket!, willChangeObjectsForKeys keys: Set<AnyHashable>!) {
        let noteKeys = Set((keys ?? []).compactMap { $0 as? String })
        handler?(.willChangeNotes(noteKeys))
    }

    func bucket(
        _ bucket: SPBucket!,
        didChangeObjectForKey key: String!,
        for changeType: SPBucketChangeType,
        memberNames: [Any]!
    ) {
        guard let key else {
            return
        }
        let change: NoteChange
        switch changeType {
        case .insert:
            change = .insert
        case .delete:
            change = .delete
        case .acknowledge:
            change = .acknowledge
        default:
            change = .update(memberNames: (memberNames ?? []).compactMap { $0 as? String })
        }
        handler?(.didChangeNote(key: key, change: change))
    }

    func bucketWillStartIndexing(_ bucket: SPBucket!) {
        handler?(.indexingStarted)
    }

    func bucketDidFinishIndexing(_ bucket: SPBucket!) {
        handler?(.indexingFinished)
    }
}
