// SPDX-License-Identifier: MIT
import SwiftUI

struct UpdateSettingsView: View {
    @Environment(\.notchTheme) private var theme
    @Bindable var updates: UpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Updates")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if let installation = updates.installation {
                    Text("\(installation.version) (\(installation.build))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.65))
                }
            }

            // A build that can't update only explains why; its controls would do nothing.
            if updates.isAvailable {
                Toggle(isOn: $updates.automaticUpdates) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Install updates automatically")
                            .font(.system(size: 11))
                        Text(updates.automaticUpdates
                             ? "Checks GitHub every few hours. Installs while the shelf is empty, or when you quit."
                             : "Checks GitHub only when you ask.")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.checkbox)
                .tint(theme.accent)
                .accessibilityLabel("Install updates automatically")
                .accessibilityHint("Checks GitHub every few hours. Installs while the shelf is empty and the notch is closed, or when you quit.")

                HStack(spacing: 10) {
                    Text("Channel")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Picker("Update channel", selection: $updates.channel) {
                        ForEach(UpdateChannel.allCases) { channel in
                            Text(channel.name).tag(channel)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .disabled(updates.isInstalled)
                    .help("Stable follows tagged releases. Nightly follows the latest build of main and also takes newer stable releases.")
                }
            }

            HStack(spacing: 8) {
                Text(status)
                    .font(.system(size: 10))
                    .foregroundStyle(isProblem ? Color.orange.opacity(0.8) : Color.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .accessibilityLabel("Update status: \(status)")
                action
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NotchStyle.subtle, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(NotchStyle.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var action: some View {
        switch updates.phase {
        case .unavailable, .installed:
            EmptyView()
        case .ready:
            actionButton("Restart to update", help: "Install now and reopen NotchShot. Shots on the shelf will be cleared.",
                         action: updates.installAndRelaunch)
        default:
            actionButton("Check now", help: "Check GitHub for a newer \(updates.channel.name.lowercased()) build.") {
                updates.checkNow()
            }
            .disabled(updates.isBusy)
        }
    }

    private func actionButton(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 11, weight: .medium))
            .buttonStyle(.plain)
            .foregroundStyle(Color.white.opacity(0.7))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(NotchStyle.subtle, in: RoundedRectangle(cornerRadius: 7))
            .fixedSize()
            .help(help)
    }

    private var isProblem: Bool {
        switch updates.phase {
        case .unavailable, .failed: return true
        default: return false
        }
    }

    private var status: String {
        switch updates.phase {
        case .unavailable(let reason):
            return reason
        case .idle:
            return updates.automaticUpdates ? "Checks shortly after launch." : "Not checked yet."
        case .checking:
            return "Checking GitHub…"
        case .upToDate:
            let checked = updates.lastChecked.map { " Checked \($0.formatted(.relative(presentation: .named)))." } ?? ""
            // Switching from nightly never downgrades; stable resumes once it is newer.
            if updates.channel == .stable, updates.installation?.channel == .nightly {
                return "No newer stable release yet. This nightly stays until one is published." + checked
            }
            return "Up to date." + checked
        case .downloading(let offer):
            return "Downloading \(offer.label)…"
        case .ready(let offer):
            return updates.automaticUpdates
                ? "\(offer.label) is ready. It installs while the shelf is empty, or when you quit."
                : "\(offer.label) is ready to install."
        case .installing(let offer):
            return "Installing \(offer.label)…"
        case .installed(let offer):
            return "\(offer.label) is installed. Quit and reopen NotchShot to start using it."
        case .failed(let message):
            return message
        }
    }
}
