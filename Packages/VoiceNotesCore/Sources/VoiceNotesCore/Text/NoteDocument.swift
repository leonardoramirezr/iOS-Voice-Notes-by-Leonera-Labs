import Foundation

/// The plain text of a note split into lines, remembering how it was terminated so it can be rebuilt exactly.
public struct NoteDocument: Equatable, Sendable {
    public var lines: [String]
    public var lineEnding: String
    public var hasTrailingNewline: Bool

    public init(lines: [String], lineEnding: String = "\n", hasTrailingNewline: Bool = false) {
        self.lines = lines
        self.lineEnding = lineEnding
        self.hasTrailingNewline = hasTrailingNewline
    }

    public init(text: String) {
        lineEnding = text.contains("\r\n") ? "\r\n" : "\n"
        guard !text.isEmpty else {
            lines = []
            hasTrailingNewline = false
            return
        }
        var parts = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        hasTrailingNewline = parts.count > 1 && parts.last == ""
        if hasTrailingNewline {
            parts.removeLast()
        }
        lines = parts
    }

    public var text: String {
        lines.joined(separator: lineEnding) + (hasTrailingNewline && !lines.isEmpty ? lineEnding : "")
    }

    /// Index of the first line that contains something other than whitespace.
    public var titleIndex: Int? {
        lines.firstIndex { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Index of the last line that contains something other than whitespace.
    public var lastContentIndex: Int? {
        lines.lastIndex { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
