import Foundation

/// A note the command changes: an existing note or one to create.
public struct ResolvedTarget: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case existing(NoteRecord)
        case new(title: String)
    }

    public let kind: Kind
    public var instruction: String

    public init(kind: Kind, instruction: String) {
        self.kind = kind
        self.instruction = instruction
    }

    public var title: String {
        switch kind {
        case .existing(let note):
            return note.title
        case .new(let title):
            return title
        }
    }

    public var isNew: Bool {
        if case .new = kind {
            return true
        }
        return false
    }
}

public enum ResolveOutcome: Equatable, Sendable {
    case targets([ResolvedTarget])
    /// The command is missing the note or the change; the message (if any) explains what is missing.
    case clarification(String?)
}

public enum PlanValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    case unknownNoteID(String)
    case missingTarget

    public var description: String {
        switch self {
        case .unknownNoteID(let id):
            return "note_id \(id) is not one of the candidates"
        case .missingTarget:
            return "each target needs note_id or new_note_title"
        }
    }
}

/// Checks the model's note choice and maps it onto real notes.
public enum PlanValidator {
    public static func validate(
        _ response: ResolveTargetsResponse,
        candidates: [Candidate],
        allNotes: [NoteRecord]
    ) throws -> ResolveOutcome {
        if response.status == .needsClarification {
            return .clarification(nonEmpty(response.message))
        }
        var resolved: [ResolvedTarget] = []
        for target in response.targets {
            let kind: ResolvedTarget.Kind
            if let id = nonEmpty(target.noteID) {
                guard let candidate = candidates.first(where: { $0.id == id }) else {
                    throw PlanValidationError.unknownNoteID(id)
                }
                kind = .existing(candidate.note)
            } else if let rawTitle = nonEmpty(target.newNoteTitle) {
                let title = NoteText.cleanTitle(rawTitle)
                if let existing = existingNote(titled: title, in: allNotes) {
                    // The model asked to create a note that already exists: change the existing one instead.
                    kind = .existing(existing)
                } else {
                    kind = .new(title: title)
                }
            } else {
                throw PlanValidationError.missingTarget
            }
            let instruction = target.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            if let index = resolved.firstIndex(where: { sameNote($0.kind, kind) }) {
                resolved[index].instruction += "\n" + instruction
            } else {
                resolved.append(ResolvedTarget(kind: kind, instruction: instruction))
            }
        }
        guard !resolved.isEmpty else {
            return .clarification(nonEmpty(response.message))
        }
        return .targets(resolved)
    }

    /// The most recently modified note whose title matches, ignoring case, accents and punctuation.
    static func existingNote(titled title: String, in notes: [NoteRecord]) -> NoteRecord? {
        let key = NoteText.normalize(title)
        guard !key.isEmpty else {
            return nil
        }
        return notes
            .filter { NoteText.normalize($0.title) == key }
            .max { $0.modificationDate < $1.modificationDate }
    }

    private static func sameNote(_ lhs: ResolvedTarget.Kind, _ rhs: ResolvedTarget.Kind) -> Bool {
        switch (lhs, rhs) {
        case (.existing(let left), .existing(let right)):
            return left.key == right.key
        case (.new(let left), .new(let right)):
            return NoteText.normalize(left) == NoteText.normalize(right)
        default:
            return false
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
