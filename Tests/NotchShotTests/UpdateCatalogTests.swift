// SPDX-License-Identifier: MIT
import Foundation
import XCTest
@testable import NotchShot

final class UpdateCatalogTests: XCTestCase {
    func testReleaseTagsDefineChannels() {
        XCTAssertEqual(UpdateChannel(releaseTag: "v0.6.0"), .stable)
        XCTAssertEqual(UpdateChannel(releaseTag: "v10.20.300"), .stable)
        XCTAssertEqual(UpdateChannel(releaseTag: "nightly-52"), .nightly)
        for ignored in ["v0.6", "v0.6.0.1", "v0.6.0-beta.1", "0.6.0", "v0..1", "vA.B.C", "nightly-", "nightly-5a",
                        "nightly-52-extra", "Nightly-52", "nightly", "v٠.٦.٠", ""] {
            XCTAssertNil(UpdateChannel(releaseTag: ignored), ignored)
        }
    }

    func testOnlyPublishedBuildChannelsCanUpdate() {
        XCTAssertEqual(UpdateChannel(buildChannel: "Stable"), .stable)
        XCTAssertEqual(UpdateChannel(buildChannel: "Preview"), .stable, "0.6.0 builds are stable-channel builds.")
        XCTAssertEqual(UpdateChannel(buildChannel: "Nightly"), .nightly)
        for local in ["Local", "stable", "", nil] as [String?] {
            XCTAssertNil(UpdateChannel(buildChannel: local))
        }
        XCTAssertEqual(UpdateChannel.stable.acceptedReleaseChannels, [.stable])
        XCTAssertEqual(UpdateChannel.nightly.acceptedReleaseChannels, [.stable, .nightly])
    }

    func testDecodesGitHubReleaseListAndPublishedManifest() throws {
        let list = """
        [{"tag_name": "v0.6.0", "draft": false, "prerelease": true,
          "published_at": "2026-09-20T09:54:53Z",
          "html_url": "https://github.com/bchewy/notchshot/releases/tag/v0.6.0",
          "assets": [{"id": 1, "name": "NotchShot-0.6.0-release.json", "size": 728, "content_type": "application/json",
                      "browser_download_url": "https://github.com/bchewy/notchshot/releases/download/v0.6.0/NotchShot-0.6.0-release.json"}]},
         {"tag_name": "nightly-40", "draft": true, "published_at": null, "html_url": null, "assets": []}]
        """
        let releases = try GitHubRelease.decodeList(Data(list.utf8))
        XCTAssertEqual(releases.map(\.tag), ["v0.6.0", "nightly-40"])
        XCTAssertEqual(releases[0].publishedAt, ISO8601DateFormatter().date(from: "2026-09-20T09:54:53Z"))
        XCTAssertEqual(releases[0].assets.first?.size, 728)
        XCTAssertTrue(releases[1].isDraft)
        XCTAssertNil(releases[1].publishedAt)
        XCTAssertThrowsError(try GitHubRelease.decodeList(Data(#"{"message": "API rate limit exceeded"}"#.utf8)))

        // The 0.6.0 manifest exactly as script/package_release.py published it.
        let manifest = try UpdateManifest.decode(Data("""
        {"artifacts": {"NotchShot-0.6.0-source.zip": "2c4a96afb0942c0aefb64f9f380bb12929a2dd95d3f8e0acae5141448e4f693e",
                       "NotchShot-0.6.0.zip": "9489e731affeda932938b169d802a782f50dcc1287f667f11bf3ded8d33aaceb"},
         "build": "29", "bundle_identifier": "com.bchewy.NotchShot", "channel": "Preview",
         "executable_sha256": "24f8ae69251d3a1f9cdbb2919ce293aceacdb8f3664b21fbad421659c6e1c03d",
         "notarization": "not_checked", "signature": "certificate-backed", "source_dirty": false,
         "source_revision": "5fd8876c4e9dbc1eaba4b4dd215965db6b5f6f77", "version": "0.6.0"}
        """.utf8))
        XCTAssertEqual(manifest.build, "29")
        XCTAssertEqual(manifest.channel, "Preview")
        XCTAssertEqual(manifest.artifacts.count, 2)
    }

    func testStableChannelConsidersOnlyTheNewestPublishedStableRelease() {
        let releases = [
            release("v0.6.0", at: 10), release("v0.7.0", at: 30), release("v0.8.0", at: 40, draft: true),
            release("nightly-60", at: 50), release("v0.9.0", at: nil), release("beta-1", at: 60),
        ]
        XCTAssertEqual(UpdateCatalog.candidates(in: releases, for: .stable).map(\.tag), ["v0.7.0"])
        XCTAssertEqual(UpdateCatalog.candidates(in: [release("nightly-60", at: 50)], for: .stable), [])
    }

    func testNightlyChannelConsidersTheNewestStableAndNightlyReleases() {
        let releases = [
            release("nightly-50", at: 20), release("v0.7.0", at: 30), release("nightly-52", at: 25),
            release("nightly-55", at: 45, draft: true),
        ]
        XCTAssertEqual(UpdateCatalog.candidates(in: releases, for: .nightly).map(\.tag), ["v0.7.0", "nightly-52"])
    }

    func testOfferDescribesAConsistentRelease() throws {
        let nightly = try UpdateCatalog.offer(release: release("nightly-52", at: 1), manifest: manifest(build: "52", channel: "Nightly"),
                                              bundleIdentifier: "com.bchewy.NotchShot")
        XCTAssertEqual(nightly.channel, .nightly)
        XCTAssertEqual(nightly.build, 52)
        XCTAssertEqual(nightly.label, "0.7.0 (52)")
        XCTAssertEqual(nightly.archiveName, "NotchShot-0.7.0.zip")
        XCTAssertEqual(nightly.archiveSHA256, String(repeating: "a", count: 64))
        XCTAssertEqual(nightly.archiveSize, 4096)
        XCTAssertEqual(nightly.archiveURL.absoluteString,
                       "https://github.com/bchewy/notchshot/releases/download/nightly-52/NotchShot-0.7.0.zip")

        let stable = try UpdateCatalog.offer(release: release("v0.7.0", at: 1), manifest: manifest(channel: "Stable"),
                                             bundleIdentifier: "com.bchewy.NotchShot")
        XCTAssertEqual(stable.channel, .stable)
        XCTAssertEqual(stable.tag, "v0.7.0")
    }

    func testDiskImageAlongsideTheArchiveDoesNotChangeTheOffer() throws {
        // Releases from 0.8.2 add a disk image for people; updates keep installing the ZIP.
        let tag = "v0.7.0"
        let withImage = release(tag, at: 1, assets: [manifestAsset(tag), archiveAsset(tag),
                                                     asset("NotchShot-0.7.0.dmg", tag: tag, size: 9000)])
        let offer = try UpdateCatalog.offer(
            release: withImage,
            manifest: manifest(artifacts: ["NotchShot-0.7.0.zip": String(repeating: "a", count: 64),
                                           "NotchShot-0.7.0.dmg": String(repeating: "c", count: 64),
                                           "NotchShot-0.7.0-source.zip": String(repeating: "b", count: 64)]),
            bundleIdentifier: "com.bchewy.NotchShot")
        XCTAssertEqual(offer.archiveName, "NotchShot-0.7.0.zip")
        XCTAssertEqual(offer.archiveSHA256, String(repeating: "a", count: 64))
        XCTAssertEqual(offer.archiveSize, 4096)
    }

    func testOfferRefusesMetadataThatDisagreesWithItsReleaseOrThisApp() {
        let bundle = "com.bchewy.NotchShot"
        let cases: [(String, GitHubRelease, UpdateManifest)] = [
            ("nightly manifest on a stable tag", release("v0.7.0", at: 1), manifest(channel: "Nightly")),
            ("stable manifest on a nightly tag", release("nightly-52", at: 1), manifest(build: "52", channel: "Stable")),
            ("local build", release("v0.7.0", at: 1), manifest(channel: "Local")),
            ("another app", release("v0.7.0", at: 1), manifest(bundleIdentifier: "com.example.Other")),
            ("version differs from tag", release("v0.7.0", at: 1), manifest(version: "0.7.1")),
            ("build differs from tag", release("nightly-52", at: 1), manifest(build: "53", channel: "Nightly")),
            ("non-numeric build", release("v0.7.0", at: 1), manifest(build: "52a")),
            ("zero build", release("v0.7.0", at: 1), manifest(build: "0")),
            ("uppercase checksum", release("v0.7.0", at: 1), manifest(hash: String(repeating: "A", count: 64))),
            ("short checksum", release("v0.7.0", at: 1), manifest(hash: "abc")),
            ("no app archive", release("v0.7.0", at: 1),
             manifest(artifacts: ["NotchShot-0.7.0-source.zip": String(repeating: "b", count: 64)])),
            ("two app archives", release("v0.7.0", at: 1),
             manifest(artifacts: ["NotchShot-0.7.0.zip": String(repeating: "a", count: 64),
                                  "NotchShot-extra.zip": String(repeating: "c", count: 64)])),
            ("archive missing from release", release("v0.7.0", at: 1, assets: [manifestAsset("v0.7.0")]), manifest()),
            ("archive hosted elsewhere", release("v0.7.0", at: 1, assets: [
                asset("NotchShot-0.7.0.zip", url: "https://example.com/bchewy/notchshot/releases/download/v0.7.0/NotchShot-0.7.0.zip"),
            ]), manifest()),
            ("archive from another release", release("v0.7.0", at: 1, assets: [
                asset("NotchShot-0.7.0.zip", url: "https://github.com/bchewy/notchshot/releases/download/v0.6.0/NotchShot-0.7.0.zip"),
            ]), manifest()),
            ("empty archive", release("v0.7.0", at: 1, assets: [archiveAsset("v0.7.0", size: 0)]), manifest()),
            ("oversized archive", release("v0.7.0", at: 1,
                                          assets: [archiveAsset("v0.7.0", size: UpdateCatalog.maximumArchiveBytes + 1)]), manifest()),
        ]
        for (name, release, manifest) in cases {
            XCTAssertThrowsError(try UpdateCatalog.offer(release: release, manifest: manifest, bundleIdentifier: bundle), name) { error in
                guard case .invalidRelease(let message) = error as? UpdateError else {
                    return XCTFail("\(name): unexpected \(error)")
                }
                XCTAssertTrue(message.hasPrefix("Release \(release.tag) "), message)
            }
        }
    }

    func testManifestMustBeOneSmallAssetFromTheSameRelease() throws {
        XCTAssertEqual(try UpdateCatalog.manifestAsset(of: release("v0.7.0", at: 1)).name, "NotchShot-0.7.0-release.json")
        let missing = release("v0.7.0", at: 1, assets: [archiveAsset("v0.7.0")])
        let duplicated = release("v0.7.0", at: 1, assets: [manifestAsset("v0.7.0"), asset("other-release.json", tag: "v0.7.0")])
        let foreign = release("v0.7.0", at: 1, assets: [manifestAsset("v0.6.0")])
        let oversized = release("v0.7.0", at: 1, assets: [asset("NotchShot-0.7.0-release.json", tag: "v0.7.0",
                                                                 size: UpdateCatalog.maximumManifestBytes + 1)])
        for release in [missing, duplicated, foreign, oversized] {
            XCTAssertThrowsError(try UpdateCatalog.manifestAsset(of: release))
        }
        XCTAssertFalse(UpdateCatalog.isDownload(URL(string: "http://github.com/bchewy/notchshot/releases/download/v0.7.0/a.zip")!,
                                                of: release("v0.7.0", at: 1)))
        XCTAssertFalse(UpdateCatalog.isDownload(URL(string: "https://github.com/bchewy/notchshot-fork/releases/download/v0.7.0/a.zip")!,
                                                of: release("v0.7.0", at: 1)))
    }

    // MARK: - Fixtures

    private func release(_ tag: String, at seconds: TimeInterval?, draft: Bool = false,
                         assets: [GitHubRelease.Asset]? = nil) -> GitHubRelease {
        GitHubRelease(tag: tag, isDraft: draft, publishedAt: seconds.map { Date(timeIntervalSince1970: $0) },
                      page: URL(string: "https://github.com/bchewy/notchshot/releases/tag/\(tag)"),
                      assets: assets ?? [manifestAsset(tag), archiveAsset(tag)])
    }

    private func manifest(version: String = "0.7.0", build: String = "52", channel: String = "Stable",
                          bundleIdentifier: String = "com.bchewy.NotchShot", hash: String = String(repeating: "a", count: 64),
                          artifacts: [String: String]? = nil) -> UpdateManifest {
        UpdateManifest(version: version, build: build, channel: channel, bundleIdentifier: bundleIdentifier,
                       sourceRevision: String(repeating: "f", count: 40),
                       artifacts: artifacts ?? ["NotchShot-0.7.0.zip": hash,
                                                "NotchShot-0.7.0-source.zip": String(repeating: "b", count: 64)])
    }

    private func manifestAsset(_ tag: String) -> GitHubRelease.Asset {
        asset("NotchShot-0.7.0-release.json", tag: tag, size: 700)
    }

    private func archiveAsset(_ tag: String, size: Int = 4096) -> GitHubRelease.Asset {
        asset("NotchShot-0.7.0.zip", tag: tag, size: size)
    }

    private func asset(_ name: String, tag: String? = nil, size: Int = 4096, url: String? = nil) -> GitHubRelease.Asset {
        GitHubRelease.Asset(name: name, size: size, downloadURL: URL(string: url
            ?? "https://github.com/bchewy/notchshot/releases/download/\(tag!)/\(name)")!)
    }
}
