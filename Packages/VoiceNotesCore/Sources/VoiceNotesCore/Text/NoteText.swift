import Foundation

/// Helpers to derive titles and previews from note content, the way Simplenote presents notes.
public enum NoteText {
    /// Maximum number of characters kept in a preview.
    public static let previewLimit = 500

    /// The first non-blank line, trimmed, without a leading Markdown heading marker.
    public static func title(of content: String) -> String {
        let document = NoteDocument(text: content)
        guard let index = document.titleIndex else {
            return ""
        }
        return stripHeading(document.lines[index].trimmingCharacters(in: .whitespaces))
    }

    /// The text after the title line with line breaks collapsed into spaces.
    public static func preview(of content: String, limit: Int = previewLimit) -> String {
        let document = NoteDocument(text: content)
        guard let index = document.titleIndex else {
            return ""
        }
        let body = document.lines[(index + 1)...]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(body.prefix(limit))
    }

    /// A comparison key that ignores case, diacritics, repeated whitespace and surrounding punctuation.
    public static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        let words = folded
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return words.trimmingCharacters(in: .punctuationCharacters.union(.symbols).union(.whitespaces))
    }

    /// Splits text into normalized words, dropping punctuation.
    public static func words(_ text: String) -> [String] {
        normalize(text)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Returns the title with its first letter capitalized and surrounding whitespace removed.
    public static func cleanTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else {
            return trimmed
        }
        return first.uppercased() + trimmed.dropFirst()
    }

    static func stripHeading(_ line: String) -> String {
        guard line.hasPrefix("#") else {
            return line
        }
        let withoutHashes = line.drop { $0 == "#" }
        guard withoutHashes.first == " " else {
            return line
        }
        return withoutHashes.trimmingCharacters(in: .whitespaces)
    }
}
