// SPDX-License-Identifier: MIT
import Foundation

/// Which published builds this copy follows. Nightly also accepts a newer stable
/// release; neither channel ever installs an older or equal build.
enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable, nightly

    var id: String { rawValue }
    var name: String { self == .stable ? "Stable" : "Nightly" }

    /// The channel a build was published on, from its signed Info.plist. Local
    /// and unknown builds have none, so they never replace themselves.
    /// `Preview` is the 0.6.0 name for what is now the stable channel.
    init?(buildChannel: String?) {
        switch buildChannel {
        case "Stable", "Preview": self = .stable
        case "Nightly": self = .nightly
        default: return nil
        }
    }

    /// Release tags are the channel contract: `v1.2.3` is stable and
    /// `nightly-<build>` is nightly. Anything else is ignored.
    init?(releaseTag tag: String) {
        if tag.hasPrefix("v"), Self.isVersion(tag.dropFirst()) {
            self = .stable
        } else if tag.hasPrefix("nightly-"), Self.isNumber(tag.dropFirst("nightly-".count)) {
            self = .nightly
        } else {
            return nil
        }
    }

    /// Release channels this one installs from.
    var acceptedReleaseChannels: [UpdateChannel] { self == .stable ? [.stable] : [.stable, .nightly] }

    static func isNumber(_ text: Substring) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func isVersion(_ text: Substring) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy(isNumber)
    }
}

/// The part of a GitHub release the updater reads.
struct GitHubRelease: Decodable, Equatable {
    struct Asset: Decodable, Equatable {
        let name: String
        let size: Int
        let downloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name, size
            case downloadURL = "browser_download_url"
        }
    }

    let tag: String
    let isDraft: Bool
    let publishedAt: Date?
    let page: URL?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tag = "tag_name"
        case isDraft = "draft"
        case publishedAt = "published_at"
        case page = "html_url"
        case assets
    }

    static func decodeList(_ data: Data) throws -> [GitHubRelease] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([GitHubRelease].self, from: data)
        } catch {
            throw UpdateError.invalidRelease("GitHub returned an unreadable release list.")
        }
    }
}

/// `NotchShot-VERSION-release.json`, written by script/package_release.py.
struct UpdateManifest: Decodable, Equatable {
    let version: String
    let build: String
    let channel: String
    let bundleIdentifier: String
    let sourceRevision: String
    let artifacts: [String: String]

    enum CodingKeys: String, CodingKey {
        case version, build, channel, artifacts
        case bundleIdentifier = "bundle_identifier"
        case sourceRevision = "source_revision"
    }

    static func decode(_ data: Data) throws -> UpdateManifest {
        do {
            return try JSONDecoder().decode(UpdateManifest.self, from: data)
        } catch {
            throw UpdateError.invalidRelease("A release manifest could not be read.")
        }
    }
}

/// A release whose metadata is consistent with this app. Nothing it describes
/// is trusted until the downloaded app passes the code-signature check.
struct UpdateOffer: Equatable {
    let channel: UpdateChannel
    let tag: String
    let version: String
    let build: Int
    let sourceRevision: String
    let archiveName: String
    let archiveURL: URL
    let archiveSHA256: String
    let archiveSize: Int
    let page: URL?

    var label: String { "\(version) (\(build))" }
}

enum UpdateError: LocalizedError, Equatable {
    case invalidRelease(String)
    case network(String)
    case verification(String)
    case installation(String)

    var errorDescription: String? {
        switch self {
        case .invalidRelease(let message), .network(let message),
             .verification(let message), .installation(let message):
            return message
        }
    }
}

/// Channel selection and release validation, kept free of I/O.
enum UpdateCatalog {
    static let repository = "bchewy/notchshot"
    static let releasesURL = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=30")!
    static let maximumListBytes = 2 * 1024 * 1024
    static let maximumManifestBytes = 64 * 1024
    static let maximumArchiveBytes = 200 * 1024 * 1024

    /// The newest published release for each channel `channel` accepts, newest
    /// first. Drafts, unpublished releases, and unrecognized tags are ignored.
    static func candidates(in releases: [GitHubRelease], for channel: UpdateChannel) -> [GitHubRelease] {
        channel.acceptedReleaseChannels.compactMap { accepted in
            releases
                .filter { !$0.isDraft && $0.publishedAt != nil && UpdateChannel(releaseTag: $0.tag) == accepted }
                .max { $0.publishedAt! < $1.publishedAt! }
        }
        .sorted { $0.publishedAt! > $1.publishedAt! }
    }

    /// The release's manifest asset. Exactly one is expected.
    static func manifestAsset(of release: GitHubRelease) throws -> GitHubRelease.Asset {
        let manifests = release.assets.filter { $0.name.hasSuffix("-release.json") }
        guard manifests.count == 1, let manifest = manifests.first,
              isDownload(manifest.downloadURL, of: release), manifest.size <= maximumManifestBytes else {
            throw UpdateError.invalidRelease("Release \(release.tag) has no usable manifest.")
        }
        return manifest
    }

    /// Cross-checks a manifest against its own release and this app. A manifest
    /// copied onto another release, or naming another app, is refused.
    static func offer(release: GitHubRelease, manifest: UpdateManifest, bundleIdentifier: String) throws -> UpdateOffer {
        func refuse(_ reason: String) -> UpdateError { .invalidRelease("Release \(release.tag) \(reason).") }

        guard let channel = UpdateChannel(releaseTag: release.tag),
              UpdateChannel(buildChannel: manifest.channel) == channel else {
            throw refuse("does not match its channel")
        }
        guard manifest.bundleIdentifier == bundleIdentifier else { throw refuse("is for another app") }
        guard UpdateChannel.isNumber(Substring(manifest.build)), let build = Int(manifest.build), build > 0 else {
            throw refuse("has an invalid build number")
        }
        switch channel {
        case .stable:
            guard release.tag == "v\(manifest.version)" else { throw refuse("does not match its version") }
        case .nightly:
            guard release.tag == "nightly-\(build)" else { throw refuse("does not match its build") }
        }
        let archives = manifest.artifacts.filter { $0.key.hasSuffix(".zip") && !$0.key.hasSuffix("-source.zip") }
        guard archives.count == 1, let archive = archives.first else {
            throw refuse("does not name one app archive")
        }
        let archiveName = archive.key, hash = archive.value
        guard hash.count == 64, hash.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
            throw refuse("has an invalid checksum")
        }
        guard let asset = release.assets.first(where: { $0.name == archiveName }),
              isDownload(asset.downloadURL, of: release) else {
            throw refuse("is missing its app archive")
        }
        guard asset.size > 0, asset.size <= maximumArchiveBytes else { throw refuse("has an unexpected archive size") }
        return UpdateOffer(channel: channel, tag: release.tag, version: manifest.version, build: build,
                           sourceRevision: manifest.sourceRevision, archiveName: archiveName,
                           archiveURL: asset.downloadURL, archiveSHA256: hash, archiveSize: asset.size,
                           page: release.page)
    }

    /// Downloads come only from this repository's own release, over HTTPS.
    static func isDownload(_ url: URL, of release: GitHubRelease) -> Bool {
        url.absoluteString.hasPrefix("https://github.com/\(repository)/releases/download/\(release.tag)/")
    }
}
