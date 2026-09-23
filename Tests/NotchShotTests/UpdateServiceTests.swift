// SPDX-License-Identifier: MIT
import Foundation
import Security
import XCTest
@testable import NotchShot

/// Real archives, checksums, extraction, and bundle swaps in a scratch folder;
/// only GitHub and the signing identity are replaced.
@MainActor
final class UpdateServiceTests: XCTestCase {
    private let bundleIdentifier = "com.example.NotchShotUpdateTests"
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchShotUpdateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testNoOfferWhenNoReleaseIsNewerThanTheInstalledBuild() async throws {
        let service = makeService(installedBuild: 40, releases: [
            (tag: "v0.6.0", at: 10, manifest: manifest(version: "0.6.0", build: 29, channel: "Preview")),
        ])
        let offer = try await service.latestOffer(for: .stable)
        XCTAssertNil(offer)
    }

    func testOfferIsTheHighestBuildAmongTheChannelsReleases() async throws {
        let releases: [(tag: String, at: TimeInterval, manifest: UpdateManifest)] = [
            ("nightly-48", 10, manifest(build: 48, channel: "Nightly")),
            ("v0.7.0", 20, manifest(build: 50)),
        ]
        let service = makeService(installedBuild: 45, releases: releases)
        let stableFromStable = try await service.latestOffer(for: .stable)
        let stableFromNightly = try await service.latestOffer(for: .nightly)
        XCTAssertEqual(stableFromStable?.tag, "v0.7.0")
        XCTAssertEqual(stableFromNightly?.tag, "v0.7.0", "Nightly takes a newer stable release.")

        let withNewerNightly = makeService(installedBuild: 45, releases: releases + [("nightly-55", 30, manifest(build: 55, channel: "Nightly"))])
        let nightly = try await withNewerNightly.latestOffer(for: .nightly)
        let stable = try await withNewerNightly.latestOffer(for: .stable)
        XCTAssertEqual(nightly?.build, 55)
        XCTAssertEqual(stable?.build, 50, "Stable never takes a nightly.")

        let onNightly = makeService(installedBuild: 55, releases: releases)
        let downgrade = try await onNightly.latestOffer(for: .stable)
        XCTAssertNil(downgrade, "Switching to stable never installs an older build.")
    }

    func testBrokenNewestReleaseIsReportedRatherThanUpToDate() async throws {
        let service = makeService(installedBuild: 50, releases: [
            ("v0.7.0", 10, manifest(build: 45)),
            ("nightly-60", 20, manifest(build: 61, channel: "Nightly")),
        ])
        do {
            _ = try await service.latestOffer(for: .nightly)
            XCTFail("A mismatched newest release must not read as up to date.")
        } catch {
            XCTAssertEqual(error as? UpdateError, .invalidRelease("Release nightly-60 does not match its build."))
        }

        let validNewer = makeService(installedBuild: 50, releases: [
            ("v0.8.0", 10, manifest(version: "0.8.0", build: 55)),
            ("nightly-60", 20, manifest(build: 61, channel: "Nightly")),
        ])
        let offer = try await validNewer.latestOffer(for: .nightly)
        XCTAssertEqual(offer?.tag, "v0.8.0", "A broken release does not hide a valid update.")
    }

    func testStagingDownloadsVerifiesAndUnpacksTheSignedApp() async throws {
        let verifier = RecordingVerifier()
        let (service, offer) = try makeStagingFixture(installedBuild: 40, updateBuild: 41, verifier: verifier)
        let staged = try await service.stage(offer)

        XCTAssertEqual(staged.offer, offer)
        XCTAssertEqual(staged.app.lastPathComponent, "NotchShot.app")
        XCTAssertEqual(try info(of: staged.app)["CFBundleVersion"] as? String, "41")
        XCTAssertEqual(try marker(of: staged.app), "build 41")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.directory.appendingPathComponent("update.zip").path),
                       "The archive is removed once unpacked.")
        XCTAssertEqual(verifier.calls, [RecordingVerifier.Call(app: staged.app, checkRevocation: true)])
    }

    func testStagingRejectsTamperedOrMismatchedDownloadsAndCleansUp() async throws {
        let cases: [(String, (inout UpdateOffer, inout URL, RecordingVerifier) throws -> Void, UpdateError)] = [
            ("checksum", { offer, _, _ in offer = offer.with(sha256: String(repeating: "0", count: 64)) },
             .verification("The update download didn’t match its published checksum. It was discarded.")),
            ("Info.plist build", { offer, archive, _ in
                archive = try self.makeArchive(build: 42, named: "mismatch")
                offer = offer.with(sha256: try UpdateService.sha256(of: archive), size: try self.size(of: archive))
            }, .verification("The downloaded app doesn’t match release v0.7.0. It was discarded.")),
            ("extra item", { offer, archive, _ in
                archive = try self.makeArchive(build: 41, named: "extra", extraItem: true)
                offer = offer.with(sha256: try UpdateService.sha256(of: archive), size: try self.size(of: archive))
            }, .verification("The update archive didn’t contain just NotchShot.app. It was discarded.")),
            ("signature", { _, _, verifier in verifier.rejects = true },
             .verification("Signature rejected.")),
        ]
        for (name, mutate, expected) in cases {
            let verifier = RecordingVerifier()
            var archive = try makeArchive(build: 41, named: "valid-\(name)")
            var offer = makeOffer(build: 41, archive: archive)
            try mutate(&offer, &archive, verifier)
            let staging = root.appendingPathComponent("staging-\(name)", isDirectory: true)
            let service = makeService(installedBuild: 40, archive: (offer.archiveURL, archive), verifier: verifier,
                                      staging: staging)
            do {
                _ = try await service.stage(offer)
                XCTFail("\(name) should be rejected")
            } catch {
                XCTAssertEqual(error as? UpdateError, expected, name)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path), "\(name): staging folder must be removed")
        }
    }

    func testInstallSwapsTheBundleInPlaceAndRemovesThePreviousApp() async throws {
        let verifier = RecordingVerifier()
        var registered: [URL] = []
        let (service, offer) = try makeStagingFixture(installedBuild: 40, updateBuild: 41, verifier: verifier,
                                                      registerApp: { registered.append($0) })
        let staged = try await service.stage(offer)
        let installed = service.installation.bundleURL
        XCTAssertEqual(try marker(of: installed), "build 40")

        try service.install(staged)

        XCTAssertEqual(try info(of: installed)["CFBundleVersion"] as? String, "41")
        XCTAssertEqual(try marker(of: installed), "build 41")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.directory.path), "The previous app is removed.")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: installed.deletingLastPathComponent().path),
                       ["NotchShot.app"], "Nothing is left beside the installed app.")
        XCTAssertEqual(verifier.calls.last, RecordingVerifier.Call(app: staged.app, checkRevocation: false),
                       "The staged app is re-verified immediately before it replaces this one.")
        XCTAssertEqual(registered, [installed])
    }

    func testInstallRefusesAnUpdateThatIsNoLongerNewerOrNoLongerValid() async throws {
        let verifier = RecordingVerifier()
        let (service, offer) = try makeStagingFixture(installedBuild: 40, updateBuild: 41, verifier: verifier)
        let staged = try await service.stage(offer)

        let newerInstall = UpdateService(installation: installation(build: 41, at: service.installation.bundleURL),
                                         transport: StubTransport(), verifier: verifier, registerApp: { _ in })
        XCTAssertThrowsError(try newerInstall.install(staged)) { error in
            XCTAssertEqual(error as? UpdateError, .installation("This update is no longer newer than the installed app."))
        }
        verifier.rejects = true
        XCTAssertThrowsError(try service.install(staged))
        XCTAssertEqual(try marker(of: service.installation.bundleURL), "build 40", "The installed app is untouched.")
    }

    func testTranslocatedOrReadOnlyInstallCannotReplaceItself() throws {
        let translocated = installation(build: 40, at: URL(fileURLWithPath: "/private/var/folders/xy/AppTranslocation/ABC/d/NotchShot.app"))
        XCTAssertEqual(translocated.installBlocker, "Move NotchShot to your Applications folder and reopen it to receive updates.")

        let folder = root.appendingPathComponent("ReadOnly", isDirectory: true)
        let app = try makeApp(build: 40, in: folder)
        XCTAssertNil(installation(build: 40, at: app).installBlocker)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        XCTAssertEqual(installation(build: 40, at: app).installBlocker,
                       "NotchShot can’t replace itself in \(folder.path). Move it to a folder you can change to receive updates.")
    }

    func testInstalledAppIdentityComesFromItsSignedInfo() throws {
        let app = try makeApp(build: 52, channel: "Nightly", in: root.appendingPathComponent("Identity", isDirectory: true))
        let identity = try XCTUnwrap(UpdateInstallation(bundle: XCTUnwrap(Bundle(url: app))))
        XCTAssertEqual(identity.bundleIdentifier, bundleIdentifier)
        XCTAssertEqual(identity.version, "0.7.0")
        XCTAssertEqual(identity.build, 52)
        XCTAssertEqual(identity.channel, .nightly)
    }

    func testCodeSignatureVerifierAppliesTheDesignatedRequirement() throws {
        // A system app stands in for a downloaded bundle; its real signature is checked.
        let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        try CodeSignatureVerifier(requirement: requirement("anchor apple")).verify(calculator, checkRevocation: false)
        XCTAssertThrowsError(try CodeSignatureVerifier(requirement: requirement(#"identifier "com.bchewy.NotchShot""#))
            .verify(calculator, checkRevocation: false))

        let unsigned = try makeApp(build: 41, in: root.appendingPathComponent("Unsigned", isDirectory: true))
        XCTAssertThrowsError(try CodeSignatureVerifier(requirement: requirement("anchor apple"))
            .verify(unsigned, checkRevocation: false))
    }

    // MARK: - Fixtures

    private func makeStagingFixture(installedBuild: Int, updateBuild: Int, verifier: RecordingVerifier,
                                    registerApp: @escaping (URL) -> Void = { _ in }) throws -> (UpdateService, UpdateOffer) {
        let archive = try makeArchive(build: updateBuild, named: "update")
        let offer = makeOffer(build: updateBuild, archive: archive)
        return (makeService(installedBuild: installedBuild, archive: (offer.archiveURL, archive), verifier: verifier,
                            registerApp: registerApp), offer)
    }

    private func makeService(installedBuild: Int,
                             releases: [(tag: String, at: TimeInterval, manifest: UpdateManifest)] = [],
                             archive: (url: URL, file: URL)? = nil,
                             verifier: RecordingVerifier = RecordingVerifier(),
                             staging: URL? = nil,
                             registerApp: @escaping (URL) -> Void = { _ in }) -> UpdateService {
        var data: [URL: Data] = [:]
        var list: [[String: Any]] = []
        for release in releases {
            let manifestURL = download(release.tag, "NotchShot-release.json")
            let archiveName = release.manifest.artifacts.keys.first { !$0.hasSuffix("-source.zip") }!
            data[manifestURL] = try! JSONSerialization.data(withJSONObject: [
                "version": release.manifest.version, "build": release.manifest.build,
                "channel": release.manifest.channel, "bundle_identifier": release.manifest.bundleIdentifier,
                "source_revision": release.manifest.sourceRevision, "artifacts": release.manifest.artifacts,
            ])
            list.append([
                "tag_name": release.tag, "draft": false,
                "published_at": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: release.at)),
                "html_url": "https://github.com/bchewy/notchshot/releases/tag/\(release.tag)",
                "assets": [
                    ["name": "NotchShot-release.json", "size": data[manifestURL]!.count,
                     "browser_download_url": manifestURL.absoluteString],
                    ["name": archiveName, "size": 4096, "browser_download_url": download(release.tag, archiveName).absoluteString],
                ],
            ])
        }
        data[UpdateCatalog.releasesURL] = try! JSONSerialization.data(withJSONObject: list)
        let installedApp = try! makeApp(build: installedBuild,
                                        in: root.appendingPathComponent("Applications-\(UUID().uuidString)", isDirectory: true))
        let stagingRoot = root!
        return UpdateService(
            installation: installation(build: installedBuild, at: installedApp),
            transport: StubTransport(data: data, files: archive.map { [$0.url: $0.file] } ?? [:]),
            verifier: verifier,
            makeStagingDirectory: {
                let directory = staging ?? stagingRoot.appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                return directory
            },
            registerApp: registerApp)
    }

    private func installation(build: Int, at app: URL) -> UpdateInstallation {
        UpdateInstallation(bundleURL: app, bundleIdentifier: bundleIdentifier, version: "0.6.0", build: build, channel: .stable)
    }

    private func manifest(version: String = "0.7.0", build: Int, channel: String = "Stable") -> UpdateManifest {
        UpdateManifest(version: version, build: String(build), channel: channel, bundleIdentifier: bundleIdentifier,
                       sourceRevision: revision,
                       artifacts: ["NotchShot-\(version).zip": String(repeating: "a", count: 64),
                                   "NotchShot-\(version)-source.zip": String(repeating: "b", count: 64)])
    }

    private func makeOffer(build: Int, archive: URL) -> UpdateOffer {
        UpdateOffer(channel: .stable, tag: "v0.7.0", version: "0.7.0", build: build, sourceRevision: revision,
                    archiveName: "NotchShot-0.7.0.zip", archiveURL: download("v0.7.0", "NotchShot-0.7.0.zip"),
                    archiveSHA256: try! UpdateService.sha256(of: archive), archiveSize: try! size(of: archive), page: nil)
    }

    private let revision = String(repeating: "c", count: 40)

    private func download(_ tag: String, _ name: String) -> URL {
        URL(string: "https://github.com/bchewy/notchshot/releases/download/\(tag)/\(name)")!
    }

    @discardableResult
    private func makeApp(build: Int, channel: String = "Stable", in folder: URL) throws -> URL {
        let app = folder.appendingPathComponent("NotchShot.app", isDirectory: true)
        let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try Data("build \(build)".utf8).write(to: macOS.appendingPathComponent("NotchShot"))
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier, "CFBundleExecutable": "NotchShot",
            "CFBundleShortVersionString": "0.7.0", "CFBundleVersion": String(build),
            "NotchShotBuildChannel": channel, "NotchShotSourceRevision": revision, "NotchShotSourceDirty": false,
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    private func makeArchive(build: Int, named name: String, extraItem: Bool = false) throws -> URL {
        let folder = root.appendingPathComponent("source-\(name)", isDirectory: true)
        let app = try makeApp(build: build, in: folder)
        let archive = root.appendingPathComponent("\(name).zip")
        if extraItem {
            try Data("surprise".utf8).write(to: folder.appendingPathComponent("README.txt"))
            try ditto(["-c", "-k", folder.path, archive.path])
        } else {
            try ditto(["-c", "-k", "--sequesterRsrc", "--keepParent", app.path, archive.path])
        }
        return archive
    }

    private func ditto(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func info(of app: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    private func marker(of app: URL) throws -> String {
        String(decoding: try Data(contentsOf: app.appendingPathComponent("Contents/MacOS/NotchShot")), as: UTF8.self)
    }

    private func size(of file: URL) throws -> Int {
        try XCTUnwrap(file.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    }

    private func requirement(_ text: String) throws -> SecRequirement {
        var requirement: SecRequirement?
        XCTAssertEqual(SecRequirementCreateWithString(text as CFString, [], &requirement), errSecSuccess)
        return try XCTUnwrap(requirement)
    }
}

private struct StubTransport: UpdateTransport {
    var data: [URL: Data] = [:]
    var files: [URL: URL] = [:]

    func data(from url: URL, limit: Int) async throws -> Data {
        guard let data = data[url] else { throw UpdateError.network("GitHub returned HTTP 404.") }
        guard data.count <= limit else { throw UpdateError.network("GitHub sent more data than expected.") }
        return data
    }

    func download(from url: URL, expectedSize: Int, to destination: URL) async throws {
        guard let file = files[url] else { throw UpdateError.network("GitHub returned HTTP 404.") }
        try FileManager.default.copyItem(at: file, to: destination)
    }
}

/// Stands in for the signing identity. Records what was verified and how.
private final class RecordingVerifier: UpdateSignatureVerifying, @unchecked Sendable {
    struct Call: Equatable {
        let app: URL
        let checkRevocation: Bool
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    private var rejecting = false

    var calls: [Call] { lock.withLock { recorded } }
    var rejects: Bool {
        get { lock.withLock { rejecting } }
        set { lock.withLock { rejecting = newValue } }
    }

    func verify(_ app: URL, checkRevocation: Bool) throws {
        try lock.withLock {
            recorded.append(Call(app: app, checkRevocation: checkRevocation))
            if rejecting { throw UpdateError.verification("Signature rejected.") }
        }
    }
}

private extension UpdateOffer {
    func with(sha256: String? = nil, size: Int? = nil) -> UpdateOffer {
        UpdateOffer(channel: channel, tag: tag, version: version, build: build, sourceRevision: sourceRevision,
                    archiveName: archiveName, archiveURL: archiveURL, archiveSHA256: sha256 ?? archiveSHA256,
                    archiveSize: size ?? archiveSize, page: page)
    }
}
