// SPDX-License-Identifier: MIT
import SwiftUI

/// The text shown here is the exact prepared context used for copying. The
/// native viewport keeps large Full copies out of SwiftUI's layout measurement.
struct BatchCopyReviewView: View {
    @Bindable var store: CaptureStore
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Review selected shots")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(NotchIconButtonStyle())
                    .accessibilityLabel("Close selection review")
            }

            if store.selectedShotCount > 0 {
                Picker("Selected shot context", selection: $store.batchContextStyle) {
                    ForEach(BatchContextStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
            }

            if let batch = store.selectedBatch {
                HStack(spacing: 8) {
                    Label("\(batch.captures.count) \(batch.captures.count == 1 ? "shot" : "shots")", systemImage: "rectangle.on.rectangle")
                    Text("\(batch.imagePNGs.count) \(batch.imagePNGs.count == 1 ? "image" : "images")")
                    Spacer()
                    Text("\(batch.characterCount.formatted()) characters")
                        .monospacedDigit()
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

                Text(disclosure(for: batch))
                    .font(.system(size: 10))
                    .foregroundStyle(batch.isShortened ? NotchStyle.accent.opacity(0.9) : Color.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)

                if !batch.omittedScreenshotNumbers.isEmpty {
                    Label {
                        Text("Screenshots unavailable for shots \(batch.omittedScreenshotNumbers.map(String.init).joined(separator: ", ")). Their text is included.")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "photo.badge.exclamationmark")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Color.orange.opacity(0.85))
                    .accessibilityElement(children: .combine)
                }

                ReadOnlyCaptureTextView(text: batch.contextText, accessibilityLabel: "Selected shot context", wrapsLines: true)
                    .frame(height: 220)
                    .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 9))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(NotchStyle.border, lineWidth: 1))

                HStack(spacing: 10) {
                    Text("Original shots and exports are unchanged.")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button {
                        if store.copyShelfSelection() { dismiss() }
                    } label: {
                        Label("Copy selected", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(NotchStyle.accent)
                    .foregroundStyle(.black)
                    .controlSize(.small)
                    .disabled(store.isPreparingBatch)
                    .accessibilityLabel("Copy \(batch.captures.count) selected shots with reviewed context")
                }
            } else if store.isPreparingBatch {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Preparing context…")
                        .font(.system(size: 11, weight: .medium))
                    Text("Preparing the selected text and screenshots for copying.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 330)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Preparing selected shot context")
            } else {
                Text("Select shots on the shelf to review their context.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            }
        }
        .padding(14)
        .frame(width: 390)
        .preferredColorScheme(.dark)
    }

    private func disclosure(for batch: CaptureBatch) -> String {
        if batch.contextStyle == .full {
            return "Full context includes each shot’s text, notes, and accessibility tree in shelf order."
        }
        if batch.isShortened {
            return "Compact: \(batch.characterCount.formatted()) characters (full: \(batch.originalCharacterCount.formatted())). Omitted, shortened, or repeated content is marked below."
        }
        return "Compact keeps useful context together, with a limit for long sections. Shots are numbered in shelf order."
    }
}
