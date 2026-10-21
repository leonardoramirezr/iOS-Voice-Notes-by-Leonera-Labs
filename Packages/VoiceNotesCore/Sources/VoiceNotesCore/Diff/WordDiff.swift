import Foundation

/// Word-level comparison of two versions of a line, used to highlight what changed inside it.
public enum WordDiff {
    public struct Segment: Equatable, Sendable {
        public let text: String
        public let isChanged: Bool

        public init(text: String, isChanged: Bool) {
            self.text = text
            self.isChanged = isChanged
        }
    }

    public static func compare(old: String, new: String) -> (old: [Segment], new: [Segment]) {
        let oldTokens = tokens(old)
        let newTokens = tokens(new)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in newTokens.difference(from: oldTokens) {
            switch change {
            case .remove(let offset, _, _):
                removed.insert(offset)
            case .insert(let offset, _, _):
                inserted.insert(offset)
            }
        }
        return (segments(oldTokens, changed: removed), segments(newTokens, changed: inserted))
    }

    /// Whether two lines share enough words to be shown as one edited line rather than a removal and an addition.
    public static func areSimilar(_ old: String, _ new: String) -> Bool {
        let oldWords = tokens(old).filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
        let newWords = tokens(new).filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
        guard !oldWords.isEmpty, !newWords.isEmpty else {
            return false
        }
        let shared = Set(oldWords).intersection(newWords).count
        return Double(shared) / Double(max(Set(oldWords).count, Set(newWords).count)) >= 0.5
    }

    /// Splits text into runs of letters/digits and single other characters (spaces, punctuation, brackets).
    static func tokens(_ text: String) -> [String] {
        var result: [String] = []
        var word = ""
        for character in text {
            if character.isLetter || character.isNumber {
                word.append(character)
            } else {
                if !word.isEmpty {
                    result.append(word)
                    word = ""
                }
                result.append(String(character))
            }
        }
        if !word.isEmpty {
            result.append(word)
        }
        return result
    }

    private static func segments(_ tokens: [String], changed: Set<Int>) -> [Segment] {
        var result: [Segment] = []
        for (index, token) in tokens.enumerated() {
            let isChanged = changed.contains(index)
            if let last = result.last, last.isChanged == isChanged {
                result[result.count - 1] = Segment(text: last.text + token, isChanged: isChanged)
            } else {
                result.append(Segment(text: token, isChanged: isChanged))
            }
        }
        return result
    }
}
