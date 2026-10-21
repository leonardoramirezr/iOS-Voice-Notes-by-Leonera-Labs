import Foundation

/// The result of applying edit steps to a note.
public struct AppliedEdit: Equatable, Sendable {
    public let newContent: String
    public let diff: [DiffLine]

    public init(newContent: String, diff: [DiffLine]) {
        self.newContent = newContent
        self.diff = diff
    }

    /// Index in `diff` of the first added or removed line.
    public var firstChangeIndex: Int? {
        diff.firstIndex(where: \.isChange)
    }
}

public enum EditApplyError: Error, Equatable, Sendable, CustomStringConvertible {
    case lineOutOfRange(line: Int, lineCount: Int)
    case anchorNotFound(line: Int, anchor: String)
    case ambiguousAnchor(String)
    case missingLine(PlanEditsResponse.Operation)
    case conflictingEdits(line: Int)
    case titleLineChange(PlanEditsResponse.Operation)
    case noChanges

    /// English explanation, sent back to the model when it is asked to fix its answer.
    public var description: String {
        switch self {
        case .lineOutOfRange(let line, let count):
            return "line \(line) does not exist; the note has \(count) lines"
        case .anchorNotFound(let line, let anchor):
            return "line \(line) is not \"\(anchor)\" and no line matches that text"
        case .ambiguousAnchor(let anchor):
            return "several lines match \"\(anchor)\"; use the exact line number and text"
        case .missingLine(let op):
            return "\(op.rawValue) needs line and anchor_text"
        case .conflictingEdits(let line):
            return "line \(line) has more than one replace, delete or set_checked edit"
        case .titleLineChange(let op):
            return "\(op.rawValue) cannot be applied to the title line"
        case .noChanges:
            return "the edits do not change the note"
        }
    }
}

/// Applies the model's edit steps deterministically and produces the unified diff for the review screen.
public enum EditApplier {
    private enum Modification: Equatable {
        case delete
        case replace([String])
        case setChecked(Bool)
    }

    /// Applies edits to an existing note. Line numbers are 1-based; `anchor_text` is used to confirm the line
    /// and to find it again when the note changed after the edits were planned.
    public static func apply(_ edits: [PlanEditsResponse.Edit], to content: String) throws -> AppliedEdit {
        let document = NoteDocument(text: content)
        let lines = document.lines
        var modifications: [Int: Modification] = [:]
        var inserts: [Int: [String]] = [:]
        var appended: [String] = []

        for edit in edits {
            switch edit.op {
            case .append:
                appended += clean(edit.lines)
            case .insertAfter:
                let index = try resolveLine(edit, in: lines)
                inserts[index, default: []] += clean(edit.lines)
            case .replace, .delete, .setChecked:
                let index = try resolveLine(edit, in: lines)
                let modification = try modification(for: edit, at: index, titleIndex: document.titleIndex)
                if let existing = modifications[index], existing != modification {
                    throw EditApplyError.conflictingEdits(line: index + 1)
                }
                modifications[index] = modification
            }
        }

        var builder = DiffBuilder()
        var output: [String] = []
        let appendAfter = document.lastContentIndex
        if appendAfter == nil {
            appended.forEach { builder.added($0) }
            output += appended
        }
        for (index, line) in lines.enumerated() {
            switch modifications[index] {
            case nil:
                builder.context(line)
                output.append(line)
            case .delete:
                builder.removed(line)
            case .replace(let newLines):
                if newLines == [line] {
                    builder.context(line)
                    output.append(line)
                } else {
                    builder.replaced(line, with: newLines)
                    output += newLines
                }
            case .setChecked(let checked):
                let updated = Checklist.setChecked(checked, line: line)
                if updated == line {
                    builder.context(line)
                    output.append(line)
                } else {
                    builder.replaced(line, with: [updated])
                    output.append(updated)
                }
            }
            for inserted in inserts[index] ?? [] {
                builder.added(inserted)
                output.append(inserted)
            }
            if index == appendAfter {
                appended.forEach { builder.added($0) }
                output += appended
            }
        }

        guard builder.lines.contains(where: \.isChange) else {
            throw EditApplyError.noChanges
        }
        let result = NoteDocument(
            lines: output, lineEnding: document.lineEnding, hasTrailingNewline: document.hasTrailingNewline
        )
        return AppliedEdit(newContent: result.text, diff: builder.lines)
    }

    /// Builds a new note: its first line is the title, followed by whatever the edits add.
    public static func applyToNewNote(title: String, edits: [PlanEditsResponse.Edit]) throws -> AppliedEdit {
        let content = edits.isEmpty ? title : try apply(edits, to: title).newContent
        let diff = NoteDocument(text: content).lines.enumerated().map {
            DiffLine(id: $0.offset, kind: .added, text: $0.element)
        }
        return AppliedEdit(newContent: content, diff: diff)
    }

    // MARK: - Helpers

    private static func modification(
        for edit: PlanEditsResponse.Edit, at index: Int, titleIndex: Int?
    ) throws -> Modification {
        switch edit.op {
        case .delete:
            if index == titleIndex {
                throw EditApplyError.titleLineChange(.delete)
            }
            return .delete
        case .setChecked:
            if index == titleIndex {
                throw EditApplyError.titleLineChange(.setChecked)
            }
            return .setChecked(edit.checked ?? true)
        default:
            let newLines = clean(edit.lines)
            if newLines.isEmpty {
                if index == titleIndex {
                    throw EditApplyError.titleLineChange(.delete)
                }
                return .delete
            }
            return .replace(newLines)
        }
    }

    static func resolveLine(_ edit: PlanEditsResponse.Edit, in lines: [String]) throws -> Int {
        let anchor = edit.anchorText?.trimmingCharacters(in: .whitespaces) ?? ""
        if let line = edit.line, line >= 1, line <= lines.count {
            if anchor.isEmpty || key(lines[line - 1]) == key(anchor) {
                return line - 1
            }
        }
        guard !anchor.isEmpty else {
            if let line = edit.line {
                throw EditApplyError.lineOutOfRange(line: line, lineCount: lines.count)
            }
            throw EditApplyError.missingLine(edit.op)
        }
        let anchorKey = key(anchor)
        let exact = lines.indices.filter { key(lines[$0]) == anchorKey }
        if exact.count == 1 {
            return exact[0]
        }
        if exact.count > 1 {
            guard let line = edit.line else {
                throw EditApplyError.ambiguousAnchor(anchor)
            }
            return exact.min { abs($0 - (line - 1)) < abs($1 - (line - 1)) } ?? exact[0]
        }
        guard anchorKey.count >= 3 else {
            throw EditApplyError.anchorNotFound(line: edit.line ?? 0, anchor: anchor)
        }
        let partial = lines.indices.filter {
            let lineKey = key(lines[$0])
            return lineKey.count >= 3 && (lineKey.contains(anchorKey) || anchorKey.contains(lineKey))
        }
        if partial.count == 1 {
            return partial[0]
        }
        if partial.count > 1 {
            throw EditApplyError.ambiguousAnchor(anchor)
        }
        throw EditApplyError.anchorNotFound(line: edit.line ?? 0, anchor: anchor)
    }

    /// Comparison key of a line: its item text without bullet or checkbox, normalized.
    static func key(_ line: String) -> String {
        NoteText.normalize(Checklist.itemText(line))
    }

    /// Splits multi-line strings, trims trailing whitespace and drops empty lines.
    static func clean(_ lines: [String]) -> [String] {
        lines
            .flatMap { $0.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") }
            .map { line in
                var line = line
                while let last = line.last, last == " " || last == "\t" {
                    line.removeLast()
                }
                return line
            }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
