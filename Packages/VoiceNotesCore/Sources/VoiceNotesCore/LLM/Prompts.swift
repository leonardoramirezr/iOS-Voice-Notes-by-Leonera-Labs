import Foundation

/// System prompts and request bodies for the two planning steps.
public enum Prompts {
    // MARK: - Step A: which notes

    public static let resolveTargetsSystem = """
    You route dictated voice commands to notes in the user's Simplenote account.

    The command was transcribed by Whisper and may contain transcription errors. The conversation can contain \
    several user messages: later ones complete or correct earlier ones. Assistant messages are questions the app \
    already asked the user.

    A note's title is its first line. "candidates" lists the notes most likely to be meant, each with an id.

    Decide which notes the command changes. For each one return a target:
    - note_id: the id of the candidate the command refers to. Match by meaning, ignoring case, accents, articles, \
    singular/plural and small transcription errors ("la nota de muebles" matches "Muebles", "lista del súper" \
    matches "Súper").
    - new_note_title: only when no candidate matches, the title of the note to create. Write a clean title with \
    the first letter capitalized and without words like "nota" or "la nota de" ("la nota de muebles" → "Muebles").
    - Exactly one of note_id and new_note_title is set; the other is null.
    - instruction: what to do in that note, in the user's language, keeping the user's exact words for any text \
    to add.
    - A command can change several notes; list each note once.

    Return status "needs_clarification" with no targets when the command does not say which note to change, or \
    does not say what to change in it. Then message is one or two short sentences in the user's language, \
    suitable to be read aloud, saying what is missing. Otherwise return status "ok" and message null.

    Only editing the text of notes and creating notes are supported. Deleting, sharing, pinning or moving whole \
    notes is not supported: ask for clarification and say so.

    language is the ISO 639-1 code of the language the user speaks.
    """

    public static func resolveTargetsInput(
        conversation: [ConversationTurn],
        candidates: [Candidate],
        today: Date
    ) -> String {
        struct Input: Encodable {
            let today: String
            let conversation: [ConversationTurn]
            let candidates: [CandidateInput]
        }
        struct CandidateInput: Encodable {
            let id: String
            let title: String
            let modified: String
        }
        return JSONCoding.string(Input(
            today: day(today),
            conversation: conversation,
            candidates: candidates.map {
                CandidateInput(id: $0.id, title: String($0.note.title.prefix(80)), modified: day($0.note.modificationDate))
            }
        ))
    }

    // MARK: - Step B: which edits

    public static let planEditsSystem = """
    You turn a dictated command into precise edit steps for plain-text Simplenote notes.

    Each target note comes with its lines numbered ("7| text"). Line 1 is usually the title. A new note only has \
    its title line. Very long notes may skip some lines; the numbers are always the real line numbers.

    Return the minimal list of edits. Operations:
    - append: add "lines" at the end of the note. line and anchor_text are null.
    - insert_after: add "lines" right after line "line" (use the title line to add at the top of the list).
    - replace: replace line "line" with "lines".
    - delete: remove line "line"; lines is [].
    - set_checked: mark line "line" as done (checked true) or not done (checked false); lines is [].
    For every operation except append, anchor_text is the exact text of that line without the number prefix. \
    checked is null except for set_checked. Use at most one replace, delete or set_checked per line.

    Writing rules:
    - Keep the user's words, names and spelling; never "correct" names or places. Only fix capitalization \
    (sentence start, proper names) and add punctuation.
    - Write in the language the user spoke. Never translate existing content.
    - New list items follow the note's list_style: "checklist" → "- [ ] Text", "bullet X" → "X Text", \
    "none" → "- Text".
    - "Add" (añade, agrega, pon, anota) means append, unless the user says where.
    - "Mark as done" (marca como completado/hecho, tacha, palomea, ya compré) means set_checked true on the \
    matching line; "unmark" means set_checked false.
    - Never change, reorder or remove anything the user did not ask for, and never change the title unless asked.

    If the line the command refers to does not exist, several lines match, or the change is unclear, return status \
    "needs_clarification" with no edits and a short message in the user's language that can be read aloud. \
    Otherwise return status "ok" and a message that summarizes the change in one short sentence in the user's \
    language.

    Examples:

    Input: {"conversation":[{"role":"user","text":"En la nota de muebles añadir en mercado Basco de Quiroga compró \
    sus muebles Brandon"}],"targets":[{"ref":"T1","title":"Muebles","is_new":true,"list_style":"none",\
    "instruction":"añadir: en mercado Basco de Quiroga compró sus muebles Brandon","numbered_lines":["1| Muebles"]}]}
    Output: {"status":"ok","message":"Agregué una línea a Muebles.","edits":[{"target":"T1","op":"append",\
    "line":null,"anchor_text":null,"lines":["- En Mercado Basco de Quiroga compró sus muebles Brandon"],\
    "checked":null}]}

    Input: {"conversation":[{"role":"user","text":"marca pan como comprado en la lista del súper"}],"targets":\
    [{"ref":"T1","title":"Súper","is_new":false,"list_style":"checklist","instruction":"marcar pan como comprado",\
    "numbered_lines":["1| Súper","2| - [ ] Leche","3| - [ ] Pan"]}]}
    Output: {"status":"ok","message":"Marqué Pan como completado.","edits":[{"target":"T1","op":"set_checked",\
    "line":3,"anchor_text":"- [ ] Pan","lines":[],"checked":true}]}

    Input: {"conversation":[{"role":"user","text":"en súper marca los huevos"}],"targets":[{"ref":"T1",\
    "title":"Súper","is_new":false,"list_style":"checklist","instruction":"marcar los huevos",\
    "numbered_lines":["1| Súper","2| - [ ] Leche"]}]}
    Output: {"status":"needs_clarification","message":"No encontré huevos en la nota Súper. ¿Qué quieres marcar?",\
    "edits":[]}
    """

    public struct PlanTarget: Encodable, Equatable, Sendable {
        public let ref: String
        public let title: String
        public let isNew: Bool
        public let listStyle: String
        public let instruction: String
        public let numberedLines: [String]

        public init(ref: String, title: String, isNew: Bool, listStyle: String, instruction: String, numberedLines: [String]) {
            self.ref = ref
            self.title = title
            self.isNew = isNew
            self.listStyle = listStyle
            self.instruction = instruction
            self.numberedLines = numberedLines
        }

        enum CodingKeys: String, CodingKey {
            case ref
            case title
            case isNew = "is_new"
            case listStyle = "list_style"
            case instruction
            case numberedLines = "numbered_lines"
        }
    }

    public static func planEditsInput(conversation: [ConversationTurn], targets: [PlanTarget]) -> String {
        struct Input: Encodable {
            let conversation: [ConversationTurn]
            let targets: [PlanTarget]
        }
        return JSONCoding.string(Input(conversation: conversation, targets: targets))
    }

    /// Appended to the step B input when its previous answer could not be applied.
    public static func repairNote(_ problem: String) -> String {
        "\n\nYour previous answer could not be applied: \(problem). Return corrected edits."
    }

    // MARK: - Transcription

    /// Whisper prompt with recent note titles, so names are spelled like the user's notes (max 224 tokens).
    public static func transcriptionPrompt(titles: [String], limit: Int = 600) -> String? {
        var prompt = ""
        for title in titles {
            let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else {
                continue
            }
            let addition = prompt.isEmpty ? clean : ", " + clean
            if prompt.count + addition.count > limit {
                break
            }
            prompt += addition
        }
        return prompt.isEmpty ? nil : prompt
    }

    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
