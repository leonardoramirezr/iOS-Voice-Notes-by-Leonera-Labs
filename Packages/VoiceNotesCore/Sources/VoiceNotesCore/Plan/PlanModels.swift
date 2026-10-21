import Foundation

/// One message of the voice conversation: what the user said, or what the app asked back.
public struct ConversationTurn: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    public var role: Role
    public var text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

public enum PlanStatus: String, Codable, Equatable, Sendable {
    case ok
    case needsClarification = "needs_clarification"
}

/// Model output of the first step: which notes the command is about.
public struct ResolveTargetsResponse: Codable, Equatable, Sendable {
    public struct Target: Codable, Equatable, Sendable {
        public var noteID: String?
        public var newNoteTitle: String?
        public var instruction: String

        public init(noteID: String?, newNoteTitle: String?, instruction: String) {
            self.noteID = noteID
            self.newNoteTitle = newNoteTitle
            self.instruction = instruction
        }

        enum CodingKeys: String, CodingKey {
            case noteID = "note_id"
            case newNoteTitle = "new_note_title"
            case instruction
        }
    }

    public var status: PlanStatus
    public var language: String
    public var message: String?
    public var targets: [Target]

    public init(status: PlanStatus, language: String, message: String?, targets: [Target]) {
        self.status = status
        self.language = language
        self.message = message
        self.targets = targets
    }
}

/// Model output of the second step: the edit steps for each target note.
public struct PlanEditsResponse: Codable, Equatable, Sendable {
    public enum Operation: String, Codable, CaseIterable, Equatable, Sendable {
        case append
        case insertAfter = "insert_after"
        case replace
        case delete
        case setChecked = "set_checked"
    }

    public struct Edit: Codable, Equatable, Sendable {
        public var target: String
        public var op: Operation
        public var line: Int?
        public var anchorText: String?
        public var lines: [String]
        public var checked: Bool?

        public init(
            target: String,
            op: Operation,
            line: Int? = nil,
            anchorText: String? = nil,
            lines: [String] = [],
            checked: Bool? = nil
        ) {
            self.target = target
            self.op = op
            self.line = line
            self.anchorText = anchorText
            self.lines = lines
            self.checked = checked
        }

        enum CodingKeys: String, CodingKey {
            case target
            case op
            case line
            case anchorText = "anchor_text"
            case lines
            case checked
        }
    }

    public var status: PlanStatus
    public var message: String?
    public var edits: [Edit]

    public init(status: PlanStatus, message: String?, edits: [Edit]) {
        self.status = status
        self.message = message
        self.edits = edits
    }
}
