// SPDX-License-Identifier: MIT
import SwiftUI

struct CaptureNotesView: View {
    let notes: [String]
    let store: CaptureStore
    var isExpanded = true
    @State private var showingDetails = false

    var body: some View {
        Button {
            showingDetails = true
        } label: {
            Label("\(notes.count)", systemImage: "exclamationmark.circle")
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 6)
                .frame(height: 24)
                .background(Color.orange.opacity(0.08), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.orange.opacity(0.9))
        .fixedSize()
        .accessibilityLabel("Read \(notes.count) capture notes")
        .help(notes.first ?? "Capture notes")
        .popover(isPresented: $showingDetails, arrowEdge: .bottom) {
            details
                .protectsNotchFromAutoCollapse(store)
        }
        .onChange(of: isExpanded) { _, expanded in
            if !expanded { showingDetails = false }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Capture notes", systemImage: "exclamationmark.circle")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    showingDetails = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(NotchIconButtonStyle())
                .accessibilityLabel("Close capture notes")
            }
            Text("These notes describe this saved capture.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(Color.orange.opacity(0.7)).frame(width: 4, height: 4).padding(.top, 5)
                            Text(note)
                                .font(.system(size: 11))
                                .lineSpacing(3)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .frame(maxHeight: 240)
        }
        .padding(16)
        .frame(width: 390)
        .preferredColorScheme(.dark)
    }
}
