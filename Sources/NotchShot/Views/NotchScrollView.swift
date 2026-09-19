// SPDX-License-Identifier: MIT
import SwiftUI

/// Retains native scrolling and momentum, with a separate, theme-matched gutter.
struct NotchScrollView<Content: View>: View {
    @Environment(\.notchTheme) private var theme
    let accessibilityLabel: String
    var onDraggingChange: (Bool) -> Void = { _ in }
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position = ScrollPosition(edge: .top)
    @State private var metrics = Metrics()
    @State private var isHovered = false
    @State private var dragOrigin: CGFloat?
    @GestureState private var isDragging = false
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollView(.vertical) {
            content
                .padding(.trailing, 16)
                .overlay(alignment: .topTrailing) {
                    if metrics.range > 1 {
                        scrollbar
                            .frame(width: 12, height: max(0, metrics.viewport - 10))
                            .padding(.top, 5)
                            .padding(.trailing, 1)
                            // Keep the rail fixed in the viewport while leaving
                            // it inside the native scroll view's event chain.
                            .offset(y: metrics.rawOffset)
                    }
                }
        }
        .scrollIndicators(.hidden, axes: .vertical)
        .defaultScrollAnchor(.top)
        .scrollPosition($position)
        .onScrollGeometryChange(for: Metrics.self) { Metrics($0) } action: { _, next in
            metrics = next
        }
        .onChange(of: isDragging) { _, dragging in
            if !dragging { dragOrigin = nil }
            onDraggingChange(dragging)
        }
        .onDisappear { onDraggingChange(false) }
    }

    private var scrollbar: some View {
        GeometryReader { geometry in
            let height = max(0, geometry.size.height)
            let thumbHeight = min(height, max(30, height * metrics.viewport / metrics.total))
            let travel = max(0, height - thumbHeight)
            let thumbY = travel * metrics.progress
            let highlighted = isHovered || isDragging || isFocused

            ZStack(alignment: .top) {
                Capsule()
                    .fill(theme.accent.opacity(highlighted ? 0.09 : 0.035))
                    .frame(width: 3)
                Capsule()
                    .fill(theme.accent.opacity(highlighted ? 0.9 : 0.42))
                    .frame(width: highlighted ? 6 : 4, height: thumbHeight)
                    .offset(y: thumbY)
            }
            .frame(width: 12, height: height, alignment: .top)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, dragging, _ in dragging = true }
                    .onChanged { value in
                        guard travel > 0 else { return }
                        if dragOrigin == nil {
                            // A rail click edits the scroll position, so it must
                            // also own subsequent arrow/Home/End key presses.
                            isFocused = true
                            // Grabbing the thumb preserves its position under the
                            // pointer; a track click centres it on the click.
                            let grabsThumb = (thumbY...(thumbY + thumbHeight)).contains(value.startLocation.y)
                            dragOrigin = grabsThumb ? metrics.offset :
                                metrics.clamped((value.startLocation.y - thumbHeight / 2) / travel * metrics.range)
                        }
                        scroll(to: (dragOrigin ?? metrics.offset) + value.translation.height / travel * metrics.range)
                    }
                    .onEnded { _ in dragOrigin = nil }
            )
            .focusable(interactions: .edit)
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.upArrow, .downArrow, .pageUp, .pageDown, .home, .end]) { key in
                switch key.key {
                case .upArrow: scroll(to: metrics.offset - 48)
                case .downArrow: scroll(to: metrics.offset + 48)
                case .pageUp: scroll(to: metrics.offset - metrics.viewport * 0.9)
                case .pageDown: scroll(to: metrics.offset + metrics.viewport * 0.9)
                case .home: scroll(to: 0)
                case .end: scroll(to: metrics.range)
                default: return .ignored
                }
                return .handled
            }
            .accessibilityRepresentation {
                Slider(value: Binding(
                    get: { Double(metrics.progress) },
                    set: { scroll(to: CGFloat($0) * metrics.range) }
                ), in: 0...1)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue("\(Int((metrics.progress * 100).rounded())) percent")
            }
            .help("Drag to scroll, or click the track to jump. Arrow keys scroll; Home and End jump to the edges.")
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: highlighted)
        }
    }

    private func scroll(to offset: CGFloat) {
        let bounded = metrics.clamped(offset)
        if bounded <= 0 {
            position.scrollTo(edge: .top)
        } else if bounded >= metrics.range {
            position.scrollTo(edge: .bottom)
        } else {
            position.scrollTo(y: bounded - metrics.topInset)
        }
    }

    private struct Metrics: Equatable {
        var total: CGFloat = 0
        var viewport: CGFloat = 0
        var offset: CGFloat = 0
        var topInset: CGFloat = 0
        var rawOffset: CGFloat = 0

        init() {}

        init(_ geometry: ScrollGeometry) {
            topInset = geometry.contentInsets.top
            rawOffset = geometry.contentOffset.y
            total = max(0, geometry.contentSize.height + topInset + geometry.contentInsets.bottom)
            viewport = max(0, geometry.containerSize.height)
            offset = min(max(0, geometry.contentOffset.y + topInset), max(0, total - viewport))
        }

        var range: CGFloat { max(0, total - viewport) }
        var progress: CGFloat { range > 0 ? offset / range : 0 }
        func clamped(_ offset: CGFloat) -> CGFloat { min(max(0, offset), range) }
    }
}
