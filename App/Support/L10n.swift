import Foundation

/// Every user-facing string. Keys and translations live in Resources/Localizable.xcstrings.
enum L10n {
    static var appName: String { String(localized: "app.name", defaultValue: "Voice Notes") }
    static var version: String { String(localized: "settings.version", defaultValue: "Version") }
    static var buildName: String { String(localized: "settings.buildName", defaultValue: "Build") }
    static var localNotes: String { String(localized: "debug.localNotes", defaultValue: "Local notes") }
}
