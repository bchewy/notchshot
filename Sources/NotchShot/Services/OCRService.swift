// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import Vision

enum OCRService {
    /// Vision runs locally. This output is intentionally kept separate from AX text.
    static func recognizeText(in image: CGImage) async throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let cancellation = RequestCancellation(request)
        return try await CaptureWorker.run(onCancel: { cancellation.cancel() }) {
            try VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }
    }

    /// Only Vision's cancellation API is accessed from another thread; request
    /// configuration is complete before the worker starts performing it.
    private final class RequestCancellation: @unchecked Sendable {
        let request: VNRequest
        init(_ request: VNRequest) { self.request = request }
        func cancel() { request.cancel() }
    }
}
