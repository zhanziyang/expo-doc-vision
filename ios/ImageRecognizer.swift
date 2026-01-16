import Foundation
import Vision
import UIKit

/// Handles OCR for image files using Apple Vision.
class ImageRecognizer {

    /// Performs OCR on an image file.
    /// - Parameters:
    ///   - url: URL to the image file
    ///   - languages: Array of language codes (BCP 47)
    ///   - mode: Recognition mode (fast or accurate)
    ///   - automaticallyDetectsLanguage: Whether to auto-detect language (iOS 16+)
    ///   - usesLanguageCorrection: Whether to use language correction
    /// - Returns: Recognized text
    static func recognize(
        imageAt url: URL,
        languages: [String],
        mode: RecognitionMode,
        automaticallyDetectsLanguage: Bool?,
        usesLanguageCorrection: Bool?
    ) throws -> String {
        guard let cgImage = loadCGImage(from: url) else {
            throw NSError(
                domain: "DOCUMENT_LOAD_FAILED",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to load image from \(url.path)"]
            )
        }

        return try performOCR(
            on: cgImage,
            languages: languages,
            mode: mode,
            automaticallyDetectsLanguage: automaticallyDetectsLanguage,
            usesLanguageCorrection: usesLanguageCorrection
        )
    }

    /// Performs OCR on a CGImage.
    /// - Parameters:
    ///   - cgImage: The image to process
    ///   - languages: Array of language codes (BCP 47)
    ///   - mode: Recognition mode (fast or accurate)
    ///   - automaticallyDetectsLanguage: Whether to auto-detect language (iOS 16+)
    ///   - usesLanguageCorrection: Whether to use language correction
    /// - Returns: Recognized text
    static func performOCR(
        on cgImage: CGImage,
        languages: [String],
        mode: RecognitionMode,
        automaticallyDetectsLanguage: Bool?,
        usesLanguageCorrection: Bool?
    ) throws -> String {
        var recognizedText = ""
        var recognitionError: Error?

        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                recognitionError = error
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }

            let lines = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }

            recognizedText = lines.joined(separator: "\n")
        }

        // Configure recognition level
        request.recognitionLevel = mode == .fast ? .fast : .accurate

        // Configure language correction (default: true)
        request.usesLanguageCorrection = usesLanguageCorrection ?? true

        // Configure languages
        if !languages.isEmpty {
            // Use specified languages
            request.recognitionLanguages = languages
            // If auto-detect is explicitly enabled, set it (iOS 16+)
            if #available(iOS 16.0, *) {
                if let autoDetect = automaticallyDetectsLanguage {
                    request.automaticallyDetectsLanguage = autoDetect
                }
            }
        } else {
            // No languages specified - enable auto-detection
            if #available(iOS 16.0, *) {
                // Default to true if not explicitly set to false
                request.automaticallyDetectsLanguage = automaticallyDetectsLanguage ?? true
                // Get all supported languages for the current revision
                if let supportedLanguages = try? request.supportedRecognitionLanguages() {
                    request.recognitionLanguages = supportedLanguages
                }
            } else if #available(iOS 15.0, *) {
                // iOS 15: no auto-detect, but we can still set all supported languages
                if let supportedLanguages = try? request.supportedRecognitionLanguages() {
                    request.recognitionLanguages = supportedLanguages
                }
            }
            // iOS 13-14: falls back to default (en-US) as supportedRecognitionLanguages requires iOS 15+
        }

        // Use revision 3 for better accuracy on iOS 16+
        if #available(iOS 16.0, *) {
            request.revision = VNRecognizeTextRequestRevision3
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            throw NSError(
                domain: "OCR_FAILED",
                code: 4,
                userInfo: [
                    NSLocalizedDescriptionKey: "OCR processing failed",
                    NSUnderlyingErrorKey: error
                ]
            )
        }

        if let error = recognitionError {
            throw error
        }

        return recognizedText
    }

    /// Loads a CGImage from a file URL.
    private static func loadCGImage(from url: URL) -> CGImage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        return CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    }
}
