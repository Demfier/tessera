import AppKit
import Security
import TesseraCore

enum UpdateError: LocalizedError {
    case server(status: Int)
    case notWritable(path: String)
    case unzipFailed
    case appMissingFromArchive
    case signatureMismatch
    case unexpectedContents

    var errorDescription: String? {
        switch self {
        case .server(let status):
            "GitHub returned HTTP \(status)."
        case .notWritable(let path):
            "Tessera can't replace itself at \(path). Move Tessera to your Applications folder, or download the update from GitHub."
        case .unzipFailed:
            "The download couldn't be unzipped."
        case .appMissingFromArchive:
            "The download doesn't contain Tessera.app."
        case .signatureMismatch:
            "The download isn't signed with the same certificate as this copy of Tessera, so it wasn't installed."
        case .unexpectedContents:
            "The download isn't the expected version of Tessera."
        }
    }
}

/// Fetches releases from GitHub and installs them over the running app.
enum UpdateInstaller {
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/Demfier/tessera/releases/latest")!

    static var currentVersion: AppVersion {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            .flatMap(AppVersion.init) ?? AppVersion("0")!
    }

    static func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: latestReleaseURL, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Tessera/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError.server(status: status) }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    /// Downloads `update`, checks it, and puts it in place of the app at `target`. A running copy of
    /// the old version keeps working until it quits; open `target` again to run the new one.
    static func install(_ update: AvailableUpdate, over target: URL) async throws {
        let files = FileManager.default
        guard files.isWritableFile(atPath: target.deletingLastPathComponent().path),
              files.isWritableFile(atPath: target.path)
        else { throw UpdateError.notWritable(path: target.deletingLastPathComponent().path) }

        let (downloaded, response) = try await URLSession.shared.download(from: update.archiveURL)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError.server(status: status) }

        // A scratch folder on the same volume as the app, so the final swap is a rename.
        let work = try files.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                 appropriateFor: target, create: true)
        defer { try? files.removeItem(at: work) }
        let archive = work.appendingPathComponent(UpdatePolicy.archiveName)
        try files.moveItem(at: downloaded, to: archive)
        try await run("/usr/bin/ditto", ["-x", "-k", archive.path, work.path])

        let app = work.appendingPathComponent("Tessera.app")
        guard files.fileExists(atPath: app.path) else { throw UpdateError.appMissingFromArchive }
        try verify(app, isVersion: update.version)
        _ = try files.replaceItemAt(target, withItemAt: app)
    }

    /// Quits this process and opens `app` once it has exited.
    @MainActor
    static func relaunch(_ app: URL) {
        let waitThenOpen = #"while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open "$2""#
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", waitThenOpen, "sh", String(getpid()), app.path]
        try? shell.run()
        NSApp.terminate(nil)
    }

    /// The new app must satisfy this app's own designated requirement: same bundle identifier, signed
    /// with the same certificate. That rules out tampered downloads, and it's also what lets macOS
    /// carry the Accessibility permission over to the new version.
    private static func verify(_ app: URL, isVersion expected: AppVersion) throws {
        var running: SecCode?
        var runningStatic: SecStaticCode?
        var requirement: SecRequirement?
        var candidate: SecStaticCode?
        guard SecCodeCopySelf([], &running) == errSecSuccess, let running,
              SecCodeCopyStaticCode(running, [], &runningStatic) == errSecSuccess, let runningStatic,
              SecCodeCopyDesignatedRequirement(runningStatic, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCreateWithPath(app as CFURL, [], &candidate) == errSecSuccess, let candidate
        else { throw UpdateError.signatureMismatch }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(candidate, flags, requirement) == errSecSuccess else {
            throw UpdateError.signatureMismatch
        }

        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              (info["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init) == expected
        else { throw UpdateError.unexpectedContents }
    }

    private static func run(_ executable: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UpdateError.unzipFailed)
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}
