import UIKit
import Vision

/// Extracts numeric text (e.g. scale/weight readings) from images using Vision OCR.
enum OCRService {

    /// Recognizes text in the image and returns the best numeric match
    /// (digits, decimal point, minus sign).
    static func recognizeNumber(from image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else { return nil }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation]
                else {
                    continuation.resume(returning: nil)
                    return
                }

                // Collect all recognized text candidates
                let allTexts = observations.compactMap { obs in
                    obs.topCandidates(1).first?.string
                }

                // Find the best numeric match (e.g. "123.4", "0.56", "-12.3")
                let numericPattern = /[\-]?\d+[\.。,]?\d*/
                for text in allTexts {
                    if let match = text.firstMatch(of: numericPattern) {
                        var result = String(match.output)
                        // Normalize full-width or Japanese decimal separators
                        result = result.replacingOccurrences(of: "。", with: ".")
                        result = result.replacingOccurrences(of: ",", with: ".")
                        return continuation.resume(returning: result)
                    }
                }

                // Fallback: return the first non-empty text
                let fallback = allTexts.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                continuation.resume(returning: fallback)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
