// SPDX-License-Identifier: MIT
import Foundation

struct AppBuildIdentity {
    static let current = AppBuildIdentity(bundle: .main)

    let label: String
    let detail: String

    init(bundle: Bundle) {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let channel = bundle.object(forInfoDictionaryKey: "NotchShotBuildChannel") as? String
        let revision = bundle.object(forInfoDictionaryKey: "NotchShotSourceRevision") as? String
        let isModified = bundle.object(forInfoDictionaryKey: "NotchShotSourceDirty") as? Bool ?? false

        var versionLabel = version ?? "Development build"
        if let build, version != nil { versionLabel += " (\(build))" }
        var components = [versionLabel]
        if let channel { components.append(channel) }
        if let revision { components.append(String(revision.prefix(7))) }
        if isModified { components.append("modified") }
        label = components.joined(separator: " · ")
        detail = revision.map { "Source commit: \($0)\(isModified ? "\nIncludes local changes." : "")" } ?? label
    }
}
