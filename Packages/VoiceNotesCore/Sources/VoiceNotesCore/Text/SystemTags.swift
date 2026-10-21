import Foundation

/// Helpers for Simplenote list fields (`tags`, `systemTags`), stored locally as JSON array strings.
public enum SystemTags {
    public static let pinned = "pinned"
    public static let markdown = "markdown"
    public static let emptyList = "[]"

    public static func decode(_ json: String?) -> [String] {
        guard let data = json?.data(using: .utf8), !data.isEmpty,
              let values = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return []
        }
        return values.compactMap { $0 as? String }
    }

    public static func encode(_ values: [String]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(values), let text = String(data: data, encoding: .utf8) else {
            return emptyList
        }
        return text
    }

    public static func contains(_ tag: String, in json: String?) -> Bool {
        decode(json).contains(tag)
    }

    /// Returns the list with `tag` added or removed, keeping every other value and its order.
    public static func setting(_ tag: String, _ enabled: Bool, in json: String?) -> String {
        var values = decode(json)
        values.removeAll { $0 == tag }
        if enabled {
            values.append(tag)
        }
        return encode(values)
    }
}
