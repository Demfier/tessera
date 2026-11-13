import Foundation
import Testing
@testable import TesseraCore

@Suite struct Versions {
    @Test func comparesNumericallyNotAlphabetically() {
        #expect(AppVersion("1.0.10")! > AppVersion("1.0.9")!)
        #expect(AppVersion("1.1")! > AppVersion("1.0.1")!)
        #expect(AppVersion("2.0")! > AppVersion("1.99.99")!)
    }

    @Test func missingComponentsCountAsZero() {
        #expect(AppVersion("1.1")! == AppVersion("1.1.0")!)
        #expect(!(AppVersion("1.1")! < AppVersion("1.1.0")!))
    }

    @Test func acceptsGitTagsAndRejectsOtherText() {
        #expect(AppVersion("v1.0.1")?.description == "1.0.1")
        #expect(AppVersion("1.0.1-beta") == nil)
        #expect(AppVersion("") == nil)
        #expect(AppVersion("1..2") == nil)
    }
}

@Suite struct Releases {
    private func release(tag: String, draft: Bool = false, prerelease: Bool = false,
                         asset: String = "Tessera.zip") throws -> GitHubRelease {
        let json = """
        {"tag_name": "\(tag)", "html_url": "https://github.com/Demfier/tessera/releases/tag/\(tag)",
         "draft": \(draft), "prerelease": \(prerelease), "name": "ignored",
         "assets": [{"name": "\(asset)", "size": 680886,
                     "browser_download_url": "https://github.com/Demfier/tessera/releases/download/\(tag)/\(asset)"}]}
        """
        return try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
    }

    @Test func newerReleaseIsOffered() throws {
        let update = try #require(UpdatePolicy.update(from: release(tag: "v1.1.0"), current: AppVersion("1.0.1")!))
        #expect(update.version == AppVersion("1.1.0")!)
        #expect(update.archiveURL.absoluteString == "https://github.com/Demfier/tessera/releases/download/v1.1.0/Tessera.zip")
        #expect(update.releaseNotesURL.absoluteString.hasSuffix("/releases/tag/v1.1.0"))
    }

    @Test func sameOrOlderReleaseIsNotOffered() throws {
        #expect(UpdatePolicy.update(from: try release(tag: "v1.0.1"), current: AppVersion("1.0.1")!) == nil)
        #expect(UpdatePolicy.update(from: try release(tag: "v1.0"), current: AppVersion("1.0.1")!) == nil)
    }

    @Test func draftsPrereleasesAndReleasesWithoutTheAppAreIgnored() throws {
        let current = AppVersion("1.0.1")!
        #expect(UpdatePolicy.update(from: try release(tag: "v2.0", draft: true), current: current) == nil)
        #expect(UpdatePolicy.update(from: try release(tag: "v2.0", prerelease: true), current: current) == nil)
        #expect(UpdatePolicy.update(from: try release(tag: "v2.0", asset: "Source.zip"), current: current) == nil)
    }
}
