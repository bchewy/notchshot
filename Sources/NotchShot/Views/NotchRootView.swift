// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

struct NotchRootView: View {
    @Bindable var store: CaptureStore
    @Bindable var presentation: NotchPresentation
    var updates: UpdateController?
    @State private var isReviewingBatch = false
    @State private var isHoveringMascot = false
    @State private var isHoveringClear = false

    var body: some View {
        ZStack(alignment: .top) {
            expandedContent
                // Keep each page at its target layout size while the native
                // panel reveals it. Large AX text never reflows on every tick.
                .frame(width: expandedSize.width, height: expandedSize.height - stripHeight)
                .opacity(contentOpacity)
                .offset(y: stripHeight - 8 * (1 - presentation.progress))
                .allowsHitTesting(store.isExpanded)
                .accessibilityHidden(!store.isExpanded)
            notchStrip
        }
        .frame(width: presentation.size.width, height: presentation.size.height, alignment: .top)
        .background(.black, in: NotchSurface())
        .clipShape(NotchSurface())
        .overlay(alignment: .bottom) {
            Capsule().fill(Color.white.opacity(0.15))
                .frame(width: 32, height: 3).padding(.bottom, 6)
                .opacity(contentOpacity)
                .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
        .tint(store.theme.accent)
        .environment(\.notchTheme, store.theme)
        .environment(updates)
        .onChange(of: store.isExpanded) { _, expanded in
            if !expanded { isReviewingBatch = false }
        }
        .onChange(of: store.isSelectingShots) { _, selecting in
            if !selecting { isReviewingBatch = false }
        }
        .onChange(of: store.page) { _, page in
            if page != .shelf { isReviewingBatch = false }
        }
    }

    private var expandedSize: CGSize { NotchStyle.expandedSize(for: store.page) }
    private var stripHeight: CGFloat { max(store.notchHeight, 32) }
    private var contentOpacity: CGFloat { max(0, min(1, (presentation.progress - 0.12) / 0.88)) }
    private var stripWingWidth: CGFloat {
        NotchStyle.collapsedWingWidth + (40 - NotchStyle.collapsedWingWidth) * presentation.progress
    }

    private var notchStrip: some View {
        HStack(spacing: 0) {
            Button(action: store.toggleExpanded) {
                HStack(spacing: 0) {
                    PhotographerMascotView(
                        pose: .resolve(isCapturing: store.isCapturing,
                                       hasPendingShot: store.pendingCapture != nil,
                                       isLanding: store.isLandingCapture),
                        camera: store.captureShutterSound,
                        expansion: presentation.progress,
                        isHovered: isHoveringMascot
                    )
                        .frame(width: stripWingWidth)
                    Color.clear.frame(width: store.notchWidth)
                }
                .frame(height: stripHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHoveringMascot = $0 }
            .accessibilityLabel(store.isExpanded ? "Collapse NotchShot" : "Open NotchShot")
            .help(store.isExpanded ? "Collapse" : "Open shot shelf · \(store.captureHintHelp)")

            if !store.captures.isEmpty || store.pendingCapture != nil {
                Button(action: store.clearHistory) {
                    Image(systemName: "trash")
                        .font(.system(size: 10 + 2 * presentation.progress, weight: .medium))
                        .foregroundStyle(isHoveringClear ? store.theme.accent : store.theme.accent.opacity(0.65))
                        .frame(width: stripWingWidth, height: stripHeight)
                        .background(isHoveringClear ? store.theme.accent.opacity(0.1) : .clear, in: Capsule())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHoveringClear = $0 }
                .onDisappear { isHoveringClear = false }
                .accessibilityLabel("Clear shot shelf")
                .accessibilityHint("Removes all saved and incoming shots. Copied content stays on your clipboard.")
                .help("Clear all shots from the shelf")
            } else {
                Button(action: store.toggleExpanded) {
                    Group {
                        if store.isCapturing {
                            ProgressView().controlSize(.mini).scaleEffect(0.55 + 0.15 * presentation.progress)
                        } else {
                            Circle()
                                .fill(store.accessibilityGranted && store.screenRecordingGranted ? store.theme.accent : Color.white.opacity(0.42))
                                .frame(width: 4 + presentation.progress, height: 4 + presentation.progress)
                        }
                    }
                    .frame(width: stripWingWidth, height: stripHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.isExpanded ? "Collapse NotchShot" : "Open NotchShot")
            }
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            switch store.page {
            case .shelf:
                ShotShelfView(store: store)
                shelfFooter
                Spacer(minLength: 0)
            case .settings:
                CaptureEmptyView(store: store, reviewingPermissions: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .detail:
                if let capture = store.selectedCapture {
                    CaptureDetailView(store: store, capture: capture)
                } else {
                    ShotShelfView(store: store)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if store.page != .shelf {
                Button(action: store.showShelf) { Image(systemName: "chevron.left") }
                    .buttonStyle(NotchIconButtonStyle())
                    .accessibilityLabel("Back to shot shelf")
                    .help("Back to shot shelf")
            }
            Text(store.page == .settings ? "Settings" : store.page == .detail ? "Shot details" : "NotchShot")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .tracking(-0.3)
            Spacer(minLength: 8)
            StatusNoticeView(notice: store.statusNotice, store: store)
            if store.page != .settings {
                Button(action: store.showCaptureSettings) { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(NotchIconButtonStyle())
                    .accessibilityLabel("NotchShot settings")
                    .help("Capture shortcut and permissions")
            }
            Button(action: store.collapse) { Image(systemName: "chevron.up") }
                .buttonStyle(NotchIconButtonStyle())
                .accessibilityLabel("Collapse NotchShot")
        }
        .frame(height: 26)
    }

    @ViewBuilder private var shelfFooter: some View {
        if store.isSelectingShots {
            selectionFooter
        } else {
            captureFooter
        }
    }

    private var canCopyShelfSelection: Bool {
        store.selectedShotCount > 0 && !store.isPreparingBatch && store.selectedBatch != nil
    }

    private var selectionFooter: some View {
        HStack(spacing: 6) {
            Button {
                isReviewingBatch = true
            } label: {
                Label("Review context", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.plain)
            .foregroundStyle(store.selectedShotCount > 0 ? store.theme.accent : Color.white.opacity(0.3))
            .disabled(store.selectedShotCount == 0)
            .help("Review the context and image count that will be copied")
            .popover(isPresented: $isReviewingBatch, arrowEdge: .bottom) {
                BatchCopyReviewView(store: store) { isReviewingBatch = false }
                    .protectsNotchFromAutoCollapse(store)
            }
            Spacer(minLength: 0)
            Text(store.selectedShotCount == 0 ? "Choose shots above" : store.isPreparingBatch ? "" : "⌘C copies selection")
                .foregroundStyle(Color.white.opacity(0.4))
                .help("Hover any shot and press Command-C to copy your selection")
            Button {
                _ = store.copyShelfSelection()
            } label: {
                Label(store.isPreparingBatch ? "Preparing…" : "Copy \(store.selectedShotCount) \(store.selectedShotCount == 1 ? "shot" : "shots")",
                      systemImage: store.isPreparingBatch ? "clock" : "doc.on.doc")
                    .foregroundStyle(canCopyShelfSelection ? Color.black : Color.white.opacity(0.3))
                    .padding(.horizontal, 7)
                    .frame(height: 19)
                    .background(canCopyShelfSelection ? store.theme.accent : NotchStyle.subtle, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canCopyShelfSelection)
            .accessibilityLabel(store.isPreparingBatch ? "Preparing selected shot context" : "Copy \(store.selectedShotCount) selected \(store.selectedShotCount == 1 ? "shot" : "shots"), \(store.copyContent.label)")
            .help(store.isPreparingBatch ? "Preparing the selected shots for copying" : "Copy \(store.copyContent.label.lowercased()) for the selected shots")
        }
        .font(.system(size: 10))
        .lineLimit(1)
        .frame(height: 16)
    }

    private var captureFooter: some View {
        HStack(spacing: 6) {
            if !store.accessibilityGranted || !store.screenRecordingGranted {
                Button(action: store.showCaptureSettings) {
                    Label("Set up capture permissions", systemImage: "lock.open")
                }
                .buttonStyle(.plain)
                .foregroundStyle(store.theme.accent)
            } else if !store.hasAvailableCaptureShortcut && !store.isRecordingShortcut {
                Button("Set a capture shortcut", action: store.showCaptureSettings)
                    .buttonStyle(.plain)
                    .foregroundStyle(store.theme.accent)
            } else {
                Label(shelfStatus, systemImage: store.isCapturing || store.isLandingCapture ? "viewfinder" : "keyboard")
                    .foregroundStyle(Color.white.opacity(0.45))
                    .help(store.isCapturing || store.isLandingCapture ? shelfStatus : store.captureHintHelp)
                    .accessibilityLabel(store.isCapturing || store.isLandingCapture ? shelfStatus : store.captureHintHelp)
            }
            Spacer(minLength: 0)
            if !store.captures.isEmpty && !store.isCapturing && !store.isLandingCapture {
                Text("Hover to preview · Click to open")
                    .foregroundStyle(Color.white.opacity(0.35))
            }
        }
        .font(.system(size: 10))
        .lineLimit(1)
        .frame(height: 16)
    }

    private var shelfStatus: String {
        if store.isCapturing { return "Reading app context…" }
        if store.isLandingCapture { return "Adding to shelf…" }
        return "\(store.captureHintLabel) to capture"
    }
}
