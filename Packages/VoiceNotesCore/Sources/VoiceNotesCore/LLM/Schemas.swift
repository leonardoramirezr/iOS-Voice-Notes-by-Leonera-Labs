import Foundation

/// JSON schemas for Groq structured outputs. They follow the strict-mode rules: every property is required,
/// optional values are unions with null and every object sets `additionalProperties: false`.
public enum PlanSchemas {
    public static let resolveTargetsName = "resolve_targets"
    public static let planEditsName = "plan_edits"

    public static func resolveTargets(candidateIDs: [String]) -> JSONValue {
        let noteID: JSONValue = candidateIDs.isEmpty
            ? ["type": "null", "description": "There are no candidate notes, so this is always null."]
            : [
                "anyOf": [["type": "string", "enum": .array(candidateIDs.map(JSONValue.string))], ["type": "null"]],
                "description": "Id of the candidate note to change, or null to create a note.",
            ]
        let target = object([
            "note_id": noteID,
            "new_note_title": [
                "type": ["string", "null"],
                "description": "Title of the note to create when no candidate matches, otherwise null.",
            ],
            "instruction": [
                "type": "string",
                "description": "What to do in this note, in the user's language, keeping the user's exact words for text to add.",
            ],
        ])
        return object([
            "status": ["type": "string", "enum": ["ok", "needs_clarification"]],
            "language": ["type": "string", "description": "ISO 639-1 code of the language the user speaks."],
            "message": [
                "type": ["string", "null"],
                "description": "Short question or problem in the user's language when clarification is needed, otherwise null.",
            ],
            "targets": ["type": "array", "items": target],
        ])
    }

    public static func planEdits(targetRefs: [String]) -> JSONValue {
        let edit = object([
            "target": ["type": "string", "enum": .array(targetRefs.map(JSONValue.string))],
            "op": ["type": "string", "enum": .array(PlanEditsResponse.Operation.allCases.map { .string($0.rawValue) })],
            "line": [
                "type": ["integer", "null"],
                "description": "1-based line number as shown in numbered_lines; null only for append.",
            ],
            "anchor_text": [
                "type": ["string", "null"],
                "description": "Exact text of that line without the number prefix; null only for append.",
            ],
            "lines": [
                "type": "array",
                "items": ["type": "string"],
                "description": "New lines for append, insert_after and replace; otherwise an empty array.",
            ],
            "checked": [
                "type": ["boolean", "null"],
                "description": "For set_checked: true marks the item as done, false as not done; otherwise null.",
            ],
        ])
        return object([
            "status": ["type": "string", "enum": ["ok", "needs_clarification"]],
            "message": [
                "type": ["string", "null"],
                "description": "Short summary of the change, or what is missing, in the user's language.",
            ],
            "edits": ["type": "array", "items": edit],
        ])
    }

    /// An object schema that requires every property and forbids extra ones.
    static func object(_ properties: [String: JSONValue]) -> JSONValue {
        [
            "type": "object",
            "properties": .object(properties),
            "required": .array(properties.keys.sorted().map(JSONValue.string)),
            "additionalProperties": false,
        ]
    }
}
