import Foundation

/// A dotted version number such as "1.0.1" (a leading "v", as in Git tags, is ignored).
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let components: [Int]

    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespaces)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        components = parts.map { $0! }
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    /// Missing components count as zero, so 1.1 == 1.1.0.
    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        let count = max(a.components.count, b.components.count)
        for i in 0..<count {
            let x = i < a.components.count ? a.components[i] : 0
            let y = i < b.components.count ? b.components[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    public static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }
}

/// The parts of GitHub's "latest release" response that Tessera uses.
public struct GitHubRelease: Decodable, Sendable {
    public struct Asset: Decodable, Sendable {
        public let name: String
        public let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    public let tagName: String
    public let htmlURL: URL
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft, prerelease, assets
    }
}

/// A release newer than the running app, with the archive to install.
public struct AvailableUpdate: Equatable, Sendable {
    public let version: AppVersion
    public let archiveURL: URL
    public let releaseNotesURL: URL
}

public enum UpdatePolicy {
    /// Name of the release asset that holds the app (see scripts/build.sh --release).
    public static let archiveName = "Tessera.zip"

    /// The update `release` offers over `current`, if any. Drafts, pre-releases, releases without
    /// the app archive, and anything not strictly newer are ignored.
    public static func update(from release: GitHubRelease, current: AppVersion) -> AvailableUpdate? {
        guard !release.draft, !release.prerelease,
              let version = AppVersion(release.tagName), version > current,
              let archive = release.assets.first(where: { $0.name == archiveName })
        else { return nil }
        return AvailableUpdate(version: version, archiveURL: archive.browserDownloadURL,
                               releaseNotesURL: release.htmlURL)
    }
}
