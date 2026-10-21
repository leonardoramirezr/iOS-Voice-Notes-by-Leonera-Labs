import Foundation

/// One line of a unified diff.
public struct DiffLine: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case context
        case added
        case removed
    }

    /// Position of the line in the diff.
    public let id: Int
    public let kind: Kind
    public let text: String
    /// Word-level highlights when the line replaces (or is replaced by) a similar line; nil otherwise.
    public let segments: [WordDiff.Segment]?

    public init(id: Int, kind: Kind, text: String, segments: [WordDiff.Segment]? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.segments = segments
    }

    public var isChange: Bool {
        kind != .context
    }
}

/// Builds diff line lists, numbering lines in order and adding word highlights to replaced line pairs.
struct DiffBuilder {
    private(set) var lines: [DiffLine] = []
    private var pending: [(kind: DiffLine.Kind, text: String)] = []

    mutating func context(_ text: String) {
        append(.context, text)
    }

    mutating func removed(_ text: String) {
        append(.removed, text)
    }

    mutating func added(_ text: String) {
        append(.added, text)
    }

    /// A line replaced by exactly one line gets word-level highlights.
    mutating func replaced(_ old: String, with new: [String]) {
        guard new.count == 1, let replacement = new.first, WordDiff.areSimilar(old, replacement) else {
            removed(old)
            new.forEach { added($0) }
            return
        }
        let segments = WordDiff.compare(old: old, new: replacement)
        lines.append(DiffLine(id: lines.count, kind: .removed, text: old, segments: segments.old))
        lines.append(DiffLine(id: lines.count, kind: .added, text: replacement, segments: segments.new))
    }

    private mutating func append(_ kind: DiffLine.Kind, _ text: String) {
        lines.append(DiffLine(id: lines.count, kind: kind, text: text))
    }
}

/// A plain line-based unified diff of two texts.
public enum LineDiff {
    public static func compute(old: String, new: String) -> [DiffLine] {
        let oldLines = NoteDocument(text: old).lines
        let newLines = NoteDocument(text: new).lines
        let difference = newLines.difference(from: oldLines)
        var removedOffsets = Set<Int>()
        var insertedOffsets = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _):
                removedOffsets.insert(offset)
            case .insert(let offset, _, _):
                insertedOffsets.insert(offset)
            }
        }
        var builder = DiffBuilder()
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < oldLines.count || newIndex < newLines.count {
            if oldIndex < oldLines.count, removedOffsets.contains(oldIndex) {
                builder.removed(oldLines[oldIndex])
                oldIndex += 1
            } else if newIndex < newLines.count, insertedOffsets.contains(newIndex) {
                builder.added(newLines[newIndex])
                newIndex += 1
            } else {
                if oldIndex < oldLines.count {
                    builder.context(oldLines[oldIndex])
                }
                oldIndex += 1
                newIndex += 1
            }
        }
        return builder.lines
    }
}
