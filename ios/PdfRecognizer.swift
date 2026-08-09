import Foundation
import PDFKit
import UIKit

struct PdfRecognitionResult {
    let text: String
    let pages: [[String: Any]]
    let source: String
}

struct PdfInfoResult {
    let pageCount: Int
    let textPageCount: Int

    var scannedPageCount: Int { pageCount - textPageCount }

    var dictionary: [String: Any] {
        [
            "pageCount": pageCount,
            "textPageCount": textPageCount,
            "scannedPageCount": scannedPageCount,
            "hasTextLayer": textPageCount > 0
        ]
    }
}

struct PdfPageRangeResult {
    let pageCount: Int
    let startPage: Int
    let endPage: Int
    let pages: [[String: Any]]

    var dictionary: [String: Any] {
        [
            "pageCount": pageCount,
            "startPage": startPage,
            "endPage": endPage,
            "pages": pages
        ]
    }
}

/// Handles PDF text extraction and Vision OCR one page at a time.
class PdfRecognizer {
    private static let maxRenderDimension: CGFloat = 2048

    static func getInfo(pdfAt url: URL) throws -> PdfInfoResult {
        let document = try loadDocument(at: url)
        var textPageCount = 0

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            if hasTextLayer(page) {
                textPageCount += 1
            }
        }

        return PdfInfoResult(pageCount: document.pageCount, textPageCount: textPageCount)
    }

    /// Backward-compatible whole-document recognition.
    /// Unlike the range API, a failed page rejects the whole operation.
    static func recognize(
        pdfAt url: URL,
        languages: [String],
        mode: RecognitionMode,
        automaticallyDetectsLanguage: Bool?,
        usesLanguageCorrection: Bool?
    ) throws -> PdfRecognitionResult {
        let document = try loadDocument(at: url)
        guard document.pageCount > 0 else {
            return PdfRecognitionResult(text: "", pages: [], source: "pdf-text")
        }

        let rangeResult = try recognizePages(
            document: document,
            startPage: 1,
            endPage: document.pageCount,
            languages: languages,
            mode: mode,
            automaticallyDetectsLanguage: automaticallyDetectsLanguage,
            usesLanguageCorrection: usesLanguageCorrection
        )

        if let failedPage = rangeResult.pages.first(where: { $0["status"] as? String == "failed" }) {
            let page = failedPage["page"] as? Int ?? 0
            let pageError = failedPage["error"] as? [String: Any]
            let message = pageError?["message"] as? String ?? "PDF page recognition failed"
            throw makeError(
                domain: pageError?["code"] as? String ?? "OCR_FAILED",
                message: "Page \(page): \(message)"
            )
        }

        let text = rangeResult.pages
            .compactMap { $0["text"] as? String }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let legacyPages = rangeResult.pages.map { pageResult in
            [
                "page": pageResult["page"] as? Int ?? 0,
                "text": pageResult["text"] as? String ?? ""
            ] as [String: Any]
        }
        let usedVision = rangeResult.pages.contains { $0["source"] as? String == "vision" }

        return PdfRecognitionResult(
            text: text,
            pages: legacyPages,
            source: usedVision ? "vision" : "pdf-text"
        )
    }

    static func recognizePages(
        pdfAt url: URL,
        startPage: Int,
        endPage: Int,
        languages: [String],
        mode: RecognitionMode,
        automaticallyDetectsLanguage: Bool?,
        usesLanguageCorrection: Bool?
    ) throws -> PdfPageRangeResult {
        let document = try loadDocument(at: url)
        return try recognizePages(
            document: document,
            startPage: startPage,
            endPage: endPage,
            languages: languages,
            mode: mode,
            automaticallyDetectsLanguage: automaticallyDetectsLanguage,
            usesLanguageCorrection: usesLanguageCorrection
        )
    }

    private static func recognizePages(
        document: PDFDocument,
        startPage: Int,
        endPage: Int,
        languages: [String],
        mode: RecognitionMode,
        automaticallyDetectsLanguage: Bool?,
        usesLanguageCorrection: Bool?
    ) throws -> PdfPageRangeResult {
        guard startPage >= 1, endPage >= startPage, endPage <= document.pageCount else {
            throw makeError(
                domain: "INVALID_OPTIONS",
                message: "Page range must satisfy 1 <= startPage <= endPage <= \(document.pageCount)"
            )
        }

        var results: [[String: Any]] = []

        for pageNumber in startPage...endPage {
            let result: [String: Any] = autoreleasepool {
                recognizePage(
                    document: document,
                    pageNumber: pageNumber,
                    languages: languages,
                    mode: mode,
                    automaticallyDetectsLanguage: automaticallyDetectsLanguage,
                    usesLanguageCorrection: usesLanguageCorrection
                )
            }
            results.append(result)
        }

        return PdfPageRangeResult(
            pageCount: document.pageCount,
            startPage: startPage,
            endPage: endPage,
            pages: results
        )
    }

    private static func recognizePage(
        document: PDFDocument,
        pageNumber: Int,
        languages: [String],
        mode: RecognitionMode,
        automaticallyDetectsLanguage: Bool?,
        usesLanguageCorrection: Bool?
    ) -> [String: Any] {
        guard let page = document.page(at: pageNumber - 1) else {
            return failedPage(
                pageNumber: pageNumber,
                source: "vision",
                error: makeError(domain: "DOCUMENT_LOAD_FAILED", message: "Failed to load PDF page")
            )
        }

        if hasTextLayer(page) {
            let text = page.string ?? ""
            return successfulPage(pageNumber: pageNumber, text: text, source: "pdf-text")
        }

        do {
            let pageImage = try renderPageToImage(page: page)
            let text = try ImageRecognizer.performOCR(
                on: pageImage,
                languages: languages,
                mode: mode,
                automaticallyDetectsLanguage: automaticallyDetectsLanguage,
                usesLanguageCorrection: usesLanguageCorrection
            )
            return successfulPage(pageNumber: pageNumber, text: text, source: "vision")
        } catch {
            return failedPage(pageNumber: pageNumber, source: "vision", error: error)
        }
    }

    private static func successfulPage(pageNumber: Int, text: String, source: String) -> [String: Any] {
        let isBlank = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return [
            "page": pageNumber,
            "text": text,
            "status": isBlank ? "blank" : "success",
            "source": source
        ]
    }

    private static func failedPage(pageNumber: Int, source: String, error: Error) -> [String: Any] {
        let nsError = error as NSError
        let code = knownErrorCode(nsError.domain)
        return [
            "page": pageNumber,
            "text": "",
            "status": "failed",
            "source": source,
            "error": [
                "code": code,
                "message": nsError.localizedDescription
            ]
        ]
    }

    private static func hasTextLayer(_ page: PDFPage) -> Bool {
        guard let text = page.string else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func loadDocument(at url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else {
            throw makeError(
                domain: "DOCUMENT_LOAD_FAILED",
                message: "Failed to load PDF from \(url.path)"
            )
        }
        return document
    }

    private static func renderPageToImage(page: PDFPage) throws -> CGImage {
        let pageRect = page.bounds(for: .mediaBox)
        let pageMaxSide = max(pageRect.width, pageRect.height)

        guard pageMaxSide > 0 else {
            throw makeError(
                domain: "DOCUMENT_LOAD_FAILED",
                message: "PDF page has invalid dimensions (zero width or height)"
            )
        }

        let scale = min(2.0, maxRenderDimension / pageMaxSide)
        let width = Int(pageRect.width * scale)
        let height = Int(pageRect.height * scale)
        guard width > 0, height > 0 else {
            throw makeError(domain: "DOCUMENT_LOAD_FAILED", message: "PDF page has invalid render dimensions")
        }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.cgContext.saveGState()
            context.cgContext.translateBy(x: 0, y: CGFloat(height))
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
            context.cgContext.restoreGState()
        }

        guard let cgImage = image.cgImage else {
            throw makeError(domain: "DOCUMENT_LOAD_FAILED", message: "Failed to render PDF page to image")
        }
        return cgImage
    }

    private static func knownErrorCode(_ domain: String) -> String {
        switch domain {
        case "DOCUMENT_LOAD_FAILED", "OCR_FAILED", "FILE_NOT_FOUND", "INVALID_OPTIONS":
            return domain
        default:
            return "OCR_FAILED"
        }
    }

    private static func makeError(domain: String, message: String) -> NSError {
        NSError(domain: domain, code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
