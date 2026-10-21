import Foundation

/// Version information injected by the build (see project.yml and the CI workflow).
enum BuildInfo {
    static var version: String {
        string(for: "CFBundleShortVersionString") ?? "0.0.0"
    }

    static var buildNumber: String {
        string(for: "CFBundleVersion") ?? "0"
    }

    /// The CI build name, e.g. `build-30-1bca82e` or `0.3.0`.
    static var buildName: String {
        string(for: "VNBuildName") ?? "local"
    }

    static var versionDescription: String {
        "\(version) (\(buildNumber))"
    }

    private static func string(for key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
