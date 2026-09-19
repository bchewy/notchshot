// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

struct ShotShelfView: View {
    @Environment(\.notchTheme) private var theme
    static let height: CGFloat = 64

    @Bindable var store: CaptureStore
    @State private var hoveredID: UUID?
    @State private var hoverPreview: ShotHoverPreviewController

    init(store: CaptureStore) {
        self.store = store
        _hoverPreview = State(initialValue: ShotHoverPreviewController(store: store))
    }

    private var canPreview: Bool {
        store.isExpanded && store.page == .shelf && !store.isCapturing &&
        !store.isLandingCapture && !store.isImporting && !store.isDropTargeted
    }

    private var incomingCapture: CaptureResult? {
        store.isLandingCapture ? store.pendingCapture : nil
    }

    private var displayedCaptures: [CaptureResult] {
        guard let incomingCapture else { return store.captures }
        return [incomingCapture] + store.captures.filter { $0.id != incomingCapture.id }
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: store.isSelectingShots ? "checkmark.circle" : "tray")
                Text(store.isSelectingShots ? "\(store.selectedShotCount) SELECTED" : "SHOT SHELF")
                    .tracking(0.8)
                Spacer()
                if store.isSelectingShots {
                    shelfAction("All", help: "Select every shot on the shelf", action: store.selectAllShelfShots)
                    shelfAction("Done", help: "Finish selecting shots", action: store.endShelfSelection)
                } else {
                    Text("\(store.captures.count)").monospacedDigit()
                    if !store.captures.isEmpty {
                        shelfAction("Select", help: "Select multiple shots to copy together", action: store.beginShelfSelection)
                    }
                }
            }
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .foregroundStyle(store.isDropTargeted ? theme.accent : Color.white.opacity(0.45))
            .frame(height: 10)

            Group {
                if (store.isDropTargeted && !store.isLandingCapture) || displayedCaptures.isEmpty {
                    dropPrompt
                } else {
                    thumbnails
                }
            }
            .frame(height: 38)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(height: Self.height)
        .background(store.isDropTargeted ? theme.accent.opacity(0.08) : NotchStyle.subtle, in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(
                    store.isDropTargeted ? theme.accent.opacity(0.9) : NotchStyle.border,
                    style: StrokeStyle(lineWidth: 1, dash: store.isDropTargeted ? [4, 4] : [])
                )
        }
        .background(ShelfSelectionKeyboardView(store: store))
        .animation(.easeOut(duration: 0.15), value: store.isDropTargeted)
        .onChange(of: canPreview) { _, enabled in
            if !enabled { dismissPreview() }
        }
        .onChange(of: displayedCaptures.map(\.id)) { _, _ in dismissPreview() }
        .onDisappear(perform: dismissPreview)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shot shelf, \(store.captures.count) saved shots")
        .accessibilityHint(store.isSelectingShots
            ? "Click shots to select them. Hover any shot and press Command-C to copy your selection. Shift-click selects a range."
            : "Drop Appshots here. Hover a shot and press Command-C to copy it; click to open its screenshot and context. Use Select to copy multiple shots.")
    }

    private func shelfAction(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button {
            dismissPreview()
            action()
        } label: {
            Text(title)
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(help)
        .help(help)
    }

    private func dismissPreview() {
        hoveredID = nil
        hoverPreview.dismiss()
    }

    private var dropPrompt: some View {
        HStack(spacing: 10) {
            Image(systemName: store.isDropTargeted ? "arrow.down.to.line" : "rectangle.on.rectangle")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(store.isDropTargeted ? theme.accent : Color.white.opacity(0.35))
            VStack(alignment: .leading, spacing: 2) {
                Text(store.isDropTargeted ? "Release to add to your shelf" : "Drop Appshots here")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(store.isDropTargeted ? theme.accent : Color.white.opacity(0.75))
                    .lineLimit(1)
                Text("Screenshot + context, together")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var thumbnails: some View {
        ScrollViewReader { scroll in
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(displayedCaptures) { capture in
                        let isIncoming = incomingCapture?.id == capture.id
                        let selectionNumber = store.selectedShelfCaptures.firstIndex { $0.id == capture.id }.map { $0 + 1 }
                        let isSelected = store.isSelectingShots
                            ? store.selectedShotIDs.contains(capture.id)
                            : store.selectedID == capture.id || (store.selectedID == nil && store.captures.first?.id == capture.id)
                        ZStack(alignment: .topTrailing) {
                            Button {
                                dismissPreview()
                                let modifiers = NSEvent.modifierFlags
                                store.handleShelfClick(capture.id,
                                    commandPressed: modifiers.contains(.command),
                                    shiftPressed: modifiers.contains(.shift))
                            } label: {
                                ShotShelfThumbnail(
                                    capture: capture,
                                    isSelected: isSelected,
                                    selectionNumber: store.isSelectingShots ? selectionNumber : nil,
                                    isIncoming: isIncoming,
                                    isHovered: canPreview && hoveredID == capture.id,
                                    store: store
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isIncoming)
                            .accessibilityLabel(isIncoming ? "Incoming \(capture.appName) shot" : "\(capture.appName), captured \(capture.date.formatted(date: .omitted, time: .shortened))")
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                            .accessibilityValue(store.isSelectingShots ? (selectionNumber.map { "Selected shot \($0)" } ?? "Not selected") : "")
                            .accessibilityHint(store.isSelectingShots ? "Click to toggle selection; Shift-click to select a range" : "Click to open details; Command-click to start selecting shots")

                            if !isIncoming {
                                Button {
                                    dismissPreview()
                                    store.removeCapture(capture.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.9))
                                        .frame(width: 16, height: 16)
                                        .background(.black.opacity(0.8), in: Circle())
                                        .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
                                        .padding(1)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(1)
                                .accessibilityLabel("Remove \(capture.appName) shot from shelf")
                                .help("Remove this shot from the shelf")
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .id(capture.id)
                        .background {
                            ShotHoverAnchorView(capture: capture, controller: hoverPreview,
                                                isEnabled: canPreview && !isIncoming,
                                                isCopyEnabled: !store.isSelectingShots || (store.selectedShotCount > 0 && !store.isPreparingBatch && store.selectedBatch != nil),
                                                copyLabel: store.isSelectingShots && store.selectedShotCount > 0 ? "Copy \(store.selectedShotCount) \(store.selectedShotCount == 1 ? "shot" : "shots")" : "Copy shot",
                                                clickLabel: store.isSelectingShots ? "Click to select" : "Click shot to open",
                                                copyShot: {
                                guard canPreview, !isIncoming else { return false }
                                return store.copyShelfShot(capture.id)
                            }) { hovering in
                                if hovering { hoveredID = capture.id }
                                else if hoveredID == capture.id { hoveredID = nil }
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: displayedCaptures.first?.id, initial: true) { _, id in
                // A receiving slot must stay visible even after browsing older
                // captures. Keep this immediate so its measured target is final.
                if let id { scroll.scrollTo(id, anchor: .leading) }
            }
        }
    }
}

private struct ShotShelfThumbnail: View {
    @Environment(\.notchTheme) private var theme
    let capture: CaptureResult
    let isSelected: Bool
    let selectionNumber: Int?
    let isIncoming: Bool
    let isHovered: Bool
    let store: CaptureStore
    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.white.opacity(0.035)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 70, height: 36)
            } else {
                Image(systemName: capture.axTree.isEmpty ? "doc.text" : "list.bullet.indent")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(width: 70, height: 26)
                    .padding(.bottom, 10)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.88)], startPoint: .top, endPoint: .bottom)
                .frame(height: 22)
            Text(capture.appName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .padding(.horizontal, 5)
                .padding(.bottom, 3)
        }
        .frame(width: 70, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .opacity(isIncoming ? 0.16 : 1)
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.accent.opacity(isHovered ? 0.10 : 0))
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isIncoming ? theme.accent.opacity(0.45) : ((isSelected || isHovered) ? theme.accent : Color.white.opacity(0.13)),
                              style: StrokeStyle(lineWidth: (isSelected || isHovered) && !isIncoming ? 1.5 : 1, dash: isIncoming ? [3, 3] : []))
        }
        .overlay(alignment: .topLeading) {
            if let selectionNumber, !isIncoming {
                Text("\(selectionNumber)")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(width: 14, height: 14)
                    .background(theme.accent, in: Circle())
                    .padding(2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .overlay {
            if isIncoming {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.accent.opacity(0.65))
                    .background(ShelfLandingTargetView(store: store, captureID: capture.id)
                        .frame(width: 70, height: 36))
            }
        }
        .animation(.easeOut(duration: 0.14), value: isIncoming)
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .padding(1)
        .task(id: capture.id) {
            image = capture.pngData.flatMap(NSImage.init(data:))
        }
    }
}
