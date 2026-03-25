import Foundation
import UIKit
@preconcurrency import Vision
import ImageIO
import CoreImage

enum OCRServiceError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Could not read that schedule page. Please try another PDF."
        }
    }
}

struct OCRService {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    func recognizeText(from image: UIImage) async throws -> OCRResult {
        guard let cgImage = image.cgImage else {
            throw OCRServiceError.invalidImage
        }

        let candidates = candidateImages(from: cgImage)
        var allLines: [OCRLine] = []
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        for candidate in candidates {
            let lines = try await recognizeTextPass(
                cgImage: candidate,
                orientation: orientation,
                usesLanguageCorrection: true
            )
            allLines.append(contentsOf: lines)
        }

        // OCR on cropped schedule pages is sometimes tiny; a second pass without
        // language correction helps preserve flight numbers and HH:mm tokens.
        if allLines.count < 250 {
            for candidate in candidates {
                let lines = try await recognizeTextPass(
                    cgImage: candidate,
                    orientation: orientation,
                    usesLanguageCorrection: false
                )
                allLines.append(contentsOf: lines)
            }
        }

        return OCRResult(lines: dedupeAndSort(allLines))
    }

    private func recognizeTextPass(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation,
        usesLanguageCorrection: Bool
    ) async throws -> [OCRLine] {
        try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            let resumeOnce: (Result<[OCRLine], Error>) -> Void = { result in
                guard !didResume else { return }
                didResume = true
                continuation.resume(with: result)
            }

            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    resumeOnce(.failure(error))
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                var lines: [OCRLine] = []

                for observation in observations {
                    guard let top = observation.topCandidates(1).first else { continue }
                    let raw = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard raw.isEmpty == false else { continue }

                    let pieces = raw
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { $0.isEmpty == false }

                    for text in pieces {
                        lines.append(
                            OCRLine(
                                text: text,
                                confidence: Double(top.confidence),
                                boundingBox: observation.boundingBox
                            )
                        )
                    }
                }

                resumeOnce(.success(lines))
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = usesLanguageCorrection
            request.minimumTextHeight = 0
            request.customWords = [
                "BKK", "HAN", "HKG", "HND", "UBP", "SIN", "LHR", "PEK", "MARCH2026",
                "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"
            ]

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    resumeOnce(.failure(error))
                }
            }
        }
    }

    private func candidateImages(from source: CGImage) -> [CGImage] {
        var candidates: [CGImage] = [source]

        let ciImage = CIImage(cgImage: source)
        let extent = ciImage.extent
        guard extent.isEmpty == false else { return candidates }

        let scales: [CGFloat]
        if extent.width < 1700 {
            scales = [2.0, 2.7]
        } else if extent.width < 2600 {
            scales = [1.8, 2.3]
        } else {
            scales = [1.5, 2.0]
        }

        for scale in scales {
            let upscaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

            let softened = upscaled
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 0.0,
                    kCIInputContrastKey: 1.35,
                    kCIInputBrightnessKey: 0.03
                ])
                .applyingFilter("CISharpenLuminance", parameters: [
                    kCIInputSharpnessKey: 0.55
                ])

            let highContrast = upscaled
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 0.0,
                    kCIInputContrastKey: 2.0,
                    kCIInputBrightnessKey: 0.02
                ])
                .applyingFilter("CIExposureAdjust", parameters: [
                    kCIInputEVKey: 0.6
                ])
                .applyingFilter("CISharpenLuminance", parameters: [
                    kCIInputSharpnessKey: 0.75
                ])

            if let raw = Self.ciContext.createCGImage(upscaled, from: upscaled.extent) {
                candidates.append(raw)
            }
            if let boosted = Self.ciContext.createCGImage(softened, from: softened.extent) {
                candidates.append(boosted)
            }
            if let boostedHighContrast = Self.ciContext.createCGImage(highContrast, from: highContrast.extent) {
                candidates.append(boostedHighContrast)
            }
        }

        return candidates
    }

    private func dedupeAndSort(_ lines: [OCRLine]) -> [OCRLine] {
        struct DedupKey: Hashable {
            let normalizedText: String
            let yBucket: Int
            let xBucket: Int
        }

        var bestByKey: [DedupKey: OCRLine] = [:]

        for line in lines {
            let key = DedupKey(
                normalizedText: normalizedText(line.text),
                yBucket: Int((line.boundingBox.midY * 100).rounded()),
                xBucket: Int((line.boundingBox.minX * 25).rounded())
            )

            if let existing = bestByKey[key], existing.confidence >= line.confidence {
                continue
            }
            bestByKey[key] = line
        }

        return bestByKey.values.sorted { lhs, rhs in
            let yDiff = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
            if yDiff > 0.02 {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
    }

    private func normalizedText(_ text: String) -> String {
        text
            .uppercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
