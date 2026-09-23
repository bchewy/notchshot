// SPDX-License-Identifier: MIT
import CoreServices
import CryptoKit
import Foundation
import Security

/// The running copy: what it is, which channel published it, and where it lives.
struct UpdateInstallation: Equatable {
    let bundleURL: URL
    let bundleIdentifier: String
    let version: String
    let build: Int
    let channel: UpdateChannel?

    init(bundleURL: URL, bundleIdentifier: String, version: String, build: Int, channel: UpdateChannel?) {
        self.bundleURL = bundleURL
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.build = build
        self.channel = channel
    }

    init?(bundle: Bundle) {
        guard let identifier = bundle.bundleIdentifier,
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let buildText = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              UpdateChannel.isNumber(Substring(buildText)), let build = Int(buildText) else { return nil }
        self.init(bundleURL: bundle.bundleURL, bundleIdentifier: identifier, version: version, build: build,
                  channel: UpdateChannel(buildChannel: bundle.object(forInfoDictionaryKey: "NotchShotBuildChannel") as? String))
    }

    /// Why this copy cannot replace itself, if it cannot. Moving a bundle needs
    /// write access to both its folder and the bundle directory itself.
    var installBlocker: String? {
        if bundleURL.path.contains("/AppTranslocation/") {
            return "Move NotchShot to your Applications folder and reopen it to receive updates."
        }
        let folder = bundleURL.deletingLastPathComponent().path
        guard FileManager.default.isWritableFile(atPath: folder),
              FileManager.default.isWritableFile(atPath: bundleURL.path) else {
            return "NotchShot can’t replace itself in \(folder). Move it to a folder you can change to receive updates."
        }
        return nil
    }
}

protocol UpdateTransport: Sendable {
    func data(from url: URL, limit: Int) async throws -> Data
    /// Leaves exactly `expectedSize` bytes at `destination`, or throws.
    func download(from url: URL, expectedSize: Int, to destination: URL) async throws
}

/// Anonymous HTTPS requests to GitHub. Nothing about captures, settings, or
/// this Mac is sent; GitHub sees an ordinary request with the app version.
struct URLSessionUpdateTransport: UpdateTransport {
    private let session: URLSession

    init(userAgent: String) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 10 * 60
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        session = URLSession(configuration: configuration)
    }

    func data(from url: URL, limit: Int) async throws -> Data {
        var request = URLRequest(url: url)
        if url.host == "api.github.com" {
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        }
        let (data, response) = try await Self.load { try await session.data(for: request) }
        try Self.check(response)
        guard data.count <= limit else { throw UpdateError.network("GitHub sent more data than expected.") }
        return data
    }

    func download(from url: URL, expectedSize: Int, to destination: URL) async throws {
        let (temporary, response) = try await Self.load { try await session.download(for: URLRequest(url: url)) }
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Self.check(response)
        guard try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize == expectedSize else {
            throw UpdateError.network("The update download was incomplete.")
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    private static func load<Value>(_ operation: () async throws -> Value) async throws -> Value {
        do {
            return try await operation()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw UpdateError.network("Couldn’t reach GitHub: \(error.localizedDescription)")
        }
    }

    private static func check(_ response: URLResponse) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            throw UpdateError.network("GitHub sent an unexpected response.")
        }
        switch status {
        case 200: return
        case 403, 429: throw UpdateError.network("GitHub is limiting update checks right now. NotchShot will try again later.")
        default: throw UpdateError.network("GitHub returned HTTP \(status).")
        }
    }
}

protocol UpdateSignatureVerifying: Sendable {
    /// Throws unless `app` is intact and signed as this same app.
    func verify(_ app: URL, checkRevocation: Bool) throws
}

/// Accepts only an app macOS itself treats as this one: the running app's own
/// designated requirement (bundle identifier and signing certificate) with
/// strict code and resource validation. Accessibility and Screen Recording
/// permissions are keyed to that same requirement, so they carry over.
struct CodeSignatureVerifier: UpdateSignatureVerifying, @unchecked Sendable {
    // SecRequirement is an immutable CF object once created.
    let requirement: SecRequirement

    /// Ad-hoc and unsigned builds have no stable identity to carry forward.
    static func forRunningApp() throws -> CodeSignatureVerifier {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let certificates = (information as? [String: Any])?[kSecCodeInfoCertificates as String] as? [Any],
              !certificates.isEmpty,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement else {
            throw UpdateError.verification("This build isn’t certificate-signed, so updates can’t be verified.")
        }
        return CodeSignatureVerifier(requirement: requirement)
    }

    func verify(_ app: URL, checkRevocation: Bool) throws {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            throw UpdateError.verification("The downloaded update isn’t a signed app. It was discarded.")
        }
        var flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        // kSecCSEnforceRevocationChecks is not imported into Swift. It rejects
        // a revoked certificate even when it shares this certificate's name.
        if checkRevocation { flags.insert(SecCSFlags(rawValue: 1 << 30)) }
        let status = SecStaticCodeCheckValidityWithErrors(staticCode, flags, requirement, nil)
        guard status == errSecSuccess else {
            throw UpdateError.verification("The downloaded update isn’t signed by NotchShot’s developer (error \(status)). It was discarded.")
        }
    }
}

/// A downloaded, verified app waiting to be swapped into place.
struct StagedUpdate: Equatable {
    let offer: UpdateOffer
    /// Removed after installing or discarding; it holds only this update.
    let directory: URL
    let app: URL
}

@MainActor
protocol UpdateServing {
    /// The newest acceptable release, or nil when this build is current.
    func latestOffer(for channel: UpdateChannel) async throws -> UpdateOffer?
    func stage(_ offer: UpdateOffer) async throws -> StagedUpdate
    func install(_ update: StagedUpdate) throws
    func discard(_ update: StagedUpdate)
}

struct UpdateService: UpdateServing {
    let installation: UpdateInstallation
    let transport: any UpdateTransport
    let verifier: any UpdateSignatureVerifying
    private let makeStagingDirectory: () throws -> URL
    private let registerApp: (URL) -> Void

    init(installation: UpdateInstallation, transport: any UpdateTransport,
         verifier: any UpdateSignatureVerifying, makeStagingDirectory: (() throws -> URL)? = nil,
         registerApp: @escaping (URL) -> Void = { _ = LSRegisterURL($0 as CFURL, true) }) {
        self.installation = installation
        self.transport = transport
        self.verifier = verifier
        self.registerApp = registerApp
        // A fresh folder on the app's own volume lets installation be a rename.
        self.makeStagingDirectory = makeStagingDirectory ?? {
            try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                        appropriateFor: installation.bundleURL, create: true)
        }
    }

    func latestOffer(for channel: UpdateChannel) async throws -> UpdateOffer? {
        let list = try await transport.data(from: UpdateCatalog.releasesURL, limit: UpdateCatalog.maximumListBytes)
        var offers: [UpdateOffer] = []
        var problem: Error?
        for release in UpdateCatalog.candidates(in: try GitHubRelease.decodeList(list), for: channel) {
            do {
                let asset = try UpdateCatalog.manifestAsset(of: release)
                let data = try await transport.data(from: asset.downloadURL, limit: UpdateCatalog.maximumManifestBytes)
                offers.append(try UpdateCatalog.offer(release: release, manifest: try UpdateManifest.decode(data),
                                                      bundleIdentifier: installation.bundleIdentifier))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                problem = problem ?? error
            }
        }
        if let newest = offers.max(by: { $0.build < $1.build }), newest.build > installation.build {
            return newest
        }
        // A broken newest release must not read as "up to date".
        if let problem { throw problem }
        return nil
    }

    func stage(_ offer: UpdateOffer) async throws -> StagedUpdate {
        let directory = try makeStagingDirectory()
        do {
            let archive = directory.appendingPathComponent("update.zip")
            try await transport.download(from: offer.archiveURL, expectedSize: offer.archiveSize, to: archive)
            let installation = installation, verifier = verifier
            let app = try await CaptureWorker.run {
                try Self.unpack(archive, into: directory, offer: offer, installation: installation, verifier: verifier)
            }
            return StagedUpdate(offer: offer, directory: directory, app: app)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func install(_ update: StagedUpdate) throws {
        if let blocker = installation.installBlocker { throw UpdateError.installation(blocker) }
        // Re-check exactly what will run next: still intact, this app, and newer.
        guard update.offer.build > installation.build else {
            throw UpdateError.installation("This update is no longer newer than the installed app.")
        }
        try Self.checkInfo(of: update.app, matches: update.offer, installation: installation)
        try verifier.verify(update.app, checkRevocation: false)
        // One atomic rename swaps the bundles. The previous app lands in the
        // staging folder, and the running process keeps its mapped executable.
        guard renamex_np(update.app.path, installation.bundleURL.path, UInt32(RENAME_SWAP)) == 0 else {
            throw UpdateError.installation("NotchShot couldn’t replace itself: \(String(cString: strerror(errno))).")
        }
        discard(update)
        // Refresh Launch Services' record so the relaunch reads the new bundle.
        registerApp(installation.bundleURL)
    }

    func discard(_ update: StagedUpdate) {
        try? FileManager.default.removeItem(at: update.directory)
    }

    nonisolated static func unpack(_ archive: URL, into directory: URL, offer: UpdateOffer,
                       installation: UpdateInstallation, verifier: any UpdateSignatureVerifying) throws -> URL {
        guard try sha256(of: archive) == offer.archiveSHA256 else {
            throw UpdateError.verification("The update download didn’t match its published checksum. It was discarded.")
        }
        let contents = directory.appendingPathComponent("app", isDirectory: true)
        try extract(archive, to: contents)
        try? FileManager.default.removeItem(at: archive)
        // ditto restores resource forks rather than leaving __MACOSX, but an
        // archive built by another tool may still include it.
        let entries = try FileManager.default.contentsOfDirectory(atPath: contents.path).filter { $0 != "__MACOSX" }
        let app = contents.appendingPathComponent("NotchShot.app", isDirectory: true)
        let kind = try? app.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard entries == ["NotchShot.app"], kind?.isDirectory == true, kind?.isSymbolicLink == false else {
            throw UpdateError.verification("The update archive didn’t contain just NotchShot.app. It was discarded.")
        }
        try checkInfo(of: app, matches: offer, installation: installation)
        try verifier.verify(app, checkRevocation: true)
        return app
    }

    /// The signature binds Info.plist, so after verification these fields are
    /// the app's own; before it they only reject an obviously wrong download.
    nonisolated static func checkInfo(of app: URL, matches offer: UpdateOffer, installation: UpdateInstallation) throws {
        guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              info["CFBundleIdentifier"] as? String == installation.bundleIdentifier,
              info["CFBundleShortVersionString"] as? String == offer.version,
              info["CFBundleVersion"] as? String == String(offer.build),
              info["NotchShotSourceRevision"] as? String == offer.sourceRevision,
              info["NotchShotSourceDirty"] as? Bool == false,
              UpdateChannel(buildChannel: info["NotchShotBuildChannel"] as? String) == offer.channel else {
            throw UpdateError.verification("The downloaded app doesn’t match release \(offer.tag). It was discarded.")
        }
    }

    nonisolated static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func extract(_ archive: URL, to destination: URL) throws {
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", archive.path, destination.path]
        ditto.standardOutput = FileHandle.nullDevice
        ditto.standardError = FileHandle.nullDevice
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            throw UpdateError.verification("The update archive couldn’t be opened. It was discarded.")
        }
    }
}
