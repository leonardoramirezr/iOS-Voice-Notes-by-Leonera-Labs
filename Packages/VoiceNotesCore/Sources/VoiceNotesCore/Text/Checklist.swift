import Foundation

/// Simplenote checklist (`- [ ] item`, `- [x] item`) and bullet list helpers.
public enum Checklist {
    /// Characters that start a bullet item.
    public static let bulletMarkers: [Character] = ["-", "*", "+", "•"]

    public enum Line: Equatable, Sendable {
        case checklist(indent: String, checked: Bool, text: String)
        case bullet(indent: String, marker: Character, text: String)
        case plain(indent: String, text: String)
    }

    public enum Style: Equatable, Sendable {
        case checklist
        case bullet(Character)
        case none

        /// The prefix used for new items written in this style.
        public var itemPrefix: String {
            switch self {
            case .checklist:
                return "- [ ] "
            case .bullet(let marker):
                return "\(marker) "
            case .none:
                return "- "
            }
        }

        /// A stable identifier sent to the language model.
        public var identifier: String {
            switch self {
            case .checklist:
                return "checklist"
            case .bullet(let marker):
                return "bullet \(marker)"
            case .none:
                return "none"
            }
        }
    }

    public static func parse(_ line: String) -> Line {
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        let rest = line.dropFirst(indent.count)
        guard let marker = rest.first, bulletMarkers.contains(marker) else {
            return .plain(indent: indent, text: String(rest))
        }
        let afterMarker = rest.dropFirst()
        guard let separator = afterMarker.first, separator == " " || separator == "\t" else {
            return .plain(indent: indent, text: String(rest))
        }
        let content = afterMarker.drop { $0 == " " || $0 == "\t" }
        if marker == "-", let box = checkbox(in: content) {
            return .checklist(indent: indent, checked: box.checked, text: box.text)
        }
        return .bullet(indent: indent, marker: marker, text: String(content))
    }

    /// Returns the line marked as checked or unchecked. Unchecking a line that is not a checklist item leaves it as is.
    public static func setChecked(_ checked: Bool, line: String) -> String {
        switch parse(line) {
        case .checklist(let indent, _, let text):
            return "\(indent)- [\(checked ? "x" : " ")] \(text)"
        case .bullet(let indent, _, let text):
            return checked ? "\(indent)- [x] \(text)" : line
        case .plain(let indent, let text):
            return checked ? "\(indent)- [x] \(text)" : line
        }
    }

    /// The item text without indentation, bullet or checkbox.
    public static func itemText(_ line: String) -> String {
        switch parse(line) {
        case .checklist(_, _, let text), .bullet(_, _, let text), .plain(_, let text):
            return text
        }
    }

    /// The dominant list style of the lines (checklists win when present).
    public static func style(of lines: [String]) -> Style {
        var counts: [Character: Int] = [:]
        var order: [Character] = []
        for line in lines {
            switch parse(line) {
            case .checklist:
                return .checklist
            case .bullet(_, let marker, _):
                if counts[marker] == nil {
                    order.append(marker)
                }
                counts[marker, default: 0] += 1
            case .plain:
                continue
            }
        }
        guard let best = order.max(by: { counts[$0, default: 0] < counts[$1, default: 0] }) else {
            return .none
        }
        return .bullet(best)
    }

    private static func checkbox(in content: Substring) -> (checked: Bool, text: String)? {
        guard content.first == "[" else {
            return nil
        }
        var index = content.index(after: content.startIndex)
        var checked = false
        if index < content.endIndex, content[index] != "]" {
            let mark = content[index]
            guard mark == " " || mark == "x" || mark == "X" else {
                return nil
            }
            checked = mark != " "
            index = content.index(after: index)
        }
        guard index < content.endIndex, content[index] == "]" else {
            return nil
        }
        let text = content[content.index(after: index)...].drop { $0 == " " || $0 == "\t" }
        return (checked, String(text))
    }
}
