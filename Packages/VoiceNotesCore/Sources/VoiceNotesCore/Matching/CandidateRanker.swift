import Foundation

/// A note known to the voice pipeline.
public struct NoteRecord: Equatable, Sendable {
    public let key: String
    public let title: String
    public let content: String
    public let modificationDate: Date

    public init(key: String, title: String, content: String, modificationDate: Date) {
        self.key = key
        self.title = title
        self.content = content
        self.modificationDate = modificationDate
    }
}

/// A note offered to the model, with a short id that is cheap to repeat and impossible to confuse with a key.
public struct Candidate: Equatable, Sendable {
    public let id: String
    public let note: NoteRecord
}

/// Picks the notes a dictated command most likely refers to, so the request stays small.
public enum CandidateRanker {
    /// Words that never identify a note.
    static let stopWords: Set<String> = [
        "a", "al", "an", "and", "de", "del", "el", "en", "for", "in", "la", "las", "lo", "los", "mi", "mis",
        "my", "note", "notes", "nota", "notas", "of", "on", "para", "por", "que", "the", "to", "tu", "un",
        "una", "y",
    ]

    public static func rank(_ notes: [NoteRecord], query: String, limit: Int = 50) -> [Candidate] {
        let normalizedQuery = NoteText.normalize(query)
        let queryWords = Set(NoteText.words(query)).subtracting(stopWords)
        let byRecency = notes.sorted { $0.modificationDate > $1.modificationDate }
        let scored = byRecency.enumerated().map { rank, note -> (score: Double, rank: Int, note: NoteRecord) in
            let recency = byRecency.count > 1 ? 5 * (1 - Double(rank) / Double(byRecency.count - 1)) : 5
            return (score(title: note.title, normalizedQuery: normalizedQuery, queryWords: queryWords) + recency, rank, note)
        }
        let best = scored
            .filter { !$0.note.title.isEmpty }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.rank < $1.rank }
            .prefix(limit)
        return best.enumerated().map { Candidate(id: "n\($0.offset + 1)", note: $0.element.note) }
    }

    static func score(title: String, normalizedQuery: String, queryWords: Set<String>) -> Double {
        let normalizedTitle = NoteText.normalize(title)
        guard !normalizedTitle.isEmpty else {
            return 0
        }
        var score = 0.0
        if normalizedQuery.contains(normalizedTitle) {
            score += 100
        }
        let titleWords = Set(NoteText.words(title)).subtracting(stopWords)
        for word in titleWords {
            if queryWords.contains(word) {
                score += 20
            } else if let best = queryWords.map({ similarity(word, $0) }).max(), best >= 0.5 {
                score += 15 * best
            }
        }
        return score
    }

    /// Character-trigram similarity (Jaccard), tolerant to plurals and small transcription errors.
    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let left = trigrams(lhs)
        let right = trigrams(rhs)
        guard !left.isEmpty, !right.isEmpty else {
            return lhs == rhs ? 1 : 0
        }
        return Double(left.intersection(right).count) / Double(left.union(right).count)
    }

    private static func trigrams(_ word: String) -> Set<String> {
        let characters = Array("  \(word) ")
        guard characters.count >= 3 else {
            return []
        }
        return Set((0...(characters.count - 3)).map { String(characters[$0..<($0 + 3)]) })
    }
}
