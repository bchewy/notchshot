// SPDX-License-Identifier: MIT
import SwiftUI

/// Attach to presented content, so its actual lifetime protects reading and
/// interaction outside the notch's own frame, including interactive dismissal.
private struct AutoCollapseProtection: ViewModifier {
    let store: CaptureStore
    @State private var owner = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { store.setAutoCollapseProtection(owner: owner, active: true) }
            .onDisappear { store.setAutoCollapseProtection(owner: owner, active: false) }
    }
}

extension View {
    func protectsNotchFromAutoCollapse(_ store: CaptureStore) -> some View {
        modifier(AutoCollapseProtection(store: store))
    }
}
