import Foundation

/// Keeps model requests small enough for Groq's per-minute token limits.
public enum ContextBudget {
    public static let maxLinesPerNote = 300
    public static let maxCharactersPerNote = 12_000
    static let tailLines = 40
    static let contextLines = 2

    /// A conservative token estimate (about 3.5 bytes per token).
    public static func estimatedTokens(_ text: String) -> Int {
        Int((Double(text.utf8.count) / 3.5).rounded(.up))
    }

    /// The note's lines prefixed with their 1-based number ("7| text"). Long notes keep the title, the lines
    /// that share words with `focus` (plus some context) and the last lines; numbers stay the real ones.
    public static func numberedLines(
        of content: String,
        focus: String,
        maxLines: Int = maxLinesPerNote,
        maxCharacters: Int = maxCharactersPerNote
    ) -> [String] {
        let lines = NoteDocument(text: content).lines
        let all = lines.enumerated().map { "\($0.offset + 1)| \($0.element)" }
        if all.count <= maxLines, all.reduce(0, { $0 + $1.count + 1 }) <= maxCharacters {
            return all
        }
        let focusWords = Set(NoteText.words(focus)).subtracting(CandidateRanker.stopWords).filter { $0.count >= 3 }
        var priority: [Int] = []
        if let title = NoteDocument(text: content).titleIndex {
            priority.append(title)
        }
        for (index, line) in lines.enumerated() where !focusWords.isDisjoint(with: NoteText.words(line)) {
            let lower = max(0, index - contextLines)
            let upper = min(lines.count - 1, index + contextLines)
            priority += Array(lower...upper)
        }
        priority += Array(max(0, lines.count - tailLines)..<lines.count)

        var selected = Set<Int>()
        var characters = 0
        for index in priority where !selected.contains(index) {
            let cost = all[index].count + 1
            if selected.count >= maxLines || characters + cost > maxCharacters {
                break
            }
            selected.insert(index)
            characters += cost
        }
        return selected.sorted().map { all[$0] }
    }
}
