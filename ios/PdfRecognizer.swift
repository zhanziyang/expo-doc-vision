import Foundation
import PDFKit
import UIKit

/// Result of PDF recognition.
struct PdfRecognitionResult {
    let text: String
    let pages: [[String: Any]]
    let source: String // "vision" or "pdf-text"
}

/// Handles OCR for PDF files using PDFKit and Vision.
class PdfRecognizer {

    /// Minimum text length to consider a PDF as text-based.
    private static let minTextLength = 20

    /// Performs OCR on a PDF file.
    /// - Parameters:
    ///   - url: URL to the PDF file
    ///   - languages: Array of language codes (BCP 47)
    ///   - mode: Recognition mode (fast or accurate)
    ///   - automaticallyDetectsLanguage: Whether to auto-detect language (iOS 16+)
    ///   - usesLanguageCorrection: Whether to use language correction
    /// - Returns: Recognition result
    static func recognize(
        pdfAt url: URL,
        languages: [String],
        mode: RecognitionMode,
        automaticallyDetectsLanguage: Bool?,
        usesLanguageCorrection: Bool?
    ) throws -> PdfRecognitionResult {
        guard let document = PDFDocument(url: url) else {
            throw NSError(
                domain: "DOCUMENT_LOAD_FAILED",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to load PDF from \(url.path)"]
            )
        }

        // Try to extract text directly from PDF
        if let pdfText = document.string, pdfText.count > minTextLength {
            // Text-based PDF - extract text per page
            return extractTextFromPdf(document: document)
        }

        // Scanned PDF - use Vision OCR
        return try recognizeScannedPdf(
            document: document,
            languages: languages,
            mode: mode,
            automaticallyDetectsLanguage: automaticallyDetectsLanguage,
            usesLanguageCorrection: usesLanguageCorrection
        )
    }

    /// Extracts text directly from a text-based PDF.
    private static func extractTextFromPdf(document: PDFDocument) -> PdfRecognitionResult {
        var pages: [[String: Any]] = []
        var allText = ""

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }

            let pageText = page.string ?? ""
            pages.append([
                "page": pageIndex + 1,
                "text": pageText
            ])

            if !allText.isEmpty && !pageText.isEmpty {
                allText += "\n\n"
            }
            allText += pageText
        }

        return PdfRecognitionResult(
            text: allText,
            pages: pages,
            source: "pdf-text"
        )
    }

    /// Recognizes text from scanned PDF pages using Vision OCR.
    private static func recognizeScannedPdf(
        document: PDFDocument,
        languages: [String],
        mode: RecognitionMode,
        automaticallyDetectsLanguage: Bool?,
        usesLanguageCorrection: Bool?
    ) throws -> PdfRecognitionResult {
        var pages: [[String: Any]] = []
        var allText = ""

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }

            let pageText: String = try autoreleasepool {
                let pageImage = try renderPageToImage(page: page)
                return try ImageRecognizer.performOCR(
                    on: pageImage,
                    languages: languages,
                    mode: mode,
                    automaticallyDetectsLanguage: automaticallyDetectsLanguage,
                    usesLanguageCorrection: usesLanguageCorrection
                )
            }

            pages.append([
                "page": pageIndex + 1,
                "text": pageText
            ])

            if !allText.isEmpty && !pageText.isEmpty {
                allText += "\n\n"
            }
            allText += pageText
        }

        return PdfRecognitionResult(
            text: allText,
            pages: pages,
            source: "vision"
        )
    }

    /// Renders a PDF page to CGImage for OCR processing.
    private static func renderPageToImage(page: PDFPage) throws -> CGImage {
        let pageRect = page.bounds(for: .mediaBox)

        // Use 2x scale for better OCR accuracy
        let scale: CGFloat = 2.0
        let width = Int(pageRect.width * scale)
        let height = Int(pageRect.height * scale)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))

        let image = renderer.image { context in
            // Fill with white background
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))

            // Save graphics state
            context.cgContext.saveGState()

            // Flip coordinate system (PDF uses bottom-left origin)
            context.cgContext.translateBy(x: 0, y: CGFloat(height))
            context.cgContext.scaleBy(x: scale, y: -scale)

            // Draw PDF page
            page.draw(with: .mediaBox, to: context.cgContext)

            // Restore graphics state
            context.cgContext.restoreGState()
        }

        guard let cgImage = image.cgImage else {
            throw NSError(
                domain: "DOCUMENT_LOAD_FAILED",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to render PDF page to image"]
            )
        }

        return cgImage
    }
}
