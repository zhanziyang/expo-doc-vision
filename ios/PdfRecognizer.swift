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
    let cancelled: Bool

    var dictionary: [String: Any] {
        [
            "pageCount": pageCount,
            "startPage": startPage,
            "endPage": endPage,
            "pages": pages,
            "cancelled": cancelled
        ]
    }
}

/// Handles PDF text extraction and Vision OCR one page at a time.
class PdfRecognizer {
    private static let maxRenderDimension: CGFloat = 2048

    static func getInfo(pdfAt url: URL) throws -> PdfInfoResult {
        let document = try loadDocument(at: url)
        return getInfo(document: document)
    }

    static func getInfo(document: PDFDocument) -> PdfInfoResult {
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
        usesLanguageCorrection: Bool?,
        maxConcurrentPages: Int
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
            usesLanguageCorrection: usesLanguageCorrection,
            maxConcurrentPages: maxConcurrentPages,
            documentLock: NSLock()
        )

        if let failedPage = rangeResult.pages.first(where: {
            let status = $0["status"] as? String
            return status == "failed" || status == "cancelled"
        }) {
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
        usesLanguageCorrection: Bool?,
        maxConcurrentPages: Int
    ) throws -> PdfPageRangeResult {
        let document = try loadDocument(at: url)
        return try recognizePages(
            document: document,
            startPage: startPage,
            endPage: endPage,
            languages: languages,
            mode: mode,
            automaticallyDetectsLanguage: automaticallyDetectsLanguage,
            usesLanguageCorrection: usesLanguageCorrection,
            maxConcurrentPages: maxConcurrentPages,
            documentLock: NSLock()
        )
    }

    static func recognizePages(
        document: PDFDocument,
        startPage: Int,
        endPage: Int,
        languages: [String],
        mode: RecognitionMode,
        automaticallyDetectsLanguage: Bool?,
        usesLanguageCorrection: Bool?,
        maxConcurrentPages: Int,
        cancellationToken: PdfCancellationToken? = nil,
        documentLock: NSLock
    ) throws -> PdfPageRangeResult {
        guard startPage >= 1, endPage >= startPage, endPage <= document.pageCount else {
            throw makeError(
                domain: "INVALID_OPTIONS",
                message: "Page range must satisfy 1 <= startPage <= endPage <= \(document.pageCount)"
            )
        }
        guard (1...2).contains(maxConcurrentPages) else {
            throw makeError(domain: "INVALID_OPTIONS", message: "maxConcurrentPages must be 1 or 2")
        }

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = maxConcurrentPages
        queue.qualityOfService = .userInitiated
        let resultStore = PdfPageResultStore()

        for pageNumber in startPage...endPage {
            queue.addOperation {
                let result: [String: Any] = autoreleasepool {
                    if cancellationToken?.isCancelled == true {
                        return cancelledPage(pageNumber: pageNumber)
                    }
                    return recognizePage(
                        document: document,
                        pageNumber: pageNumber,
                        languages: languages,
                        mode: mode,
                        automaticallyDetectsLanguage: automaticallyDetectsLanguage,
                        usesLanguageCorrection: usesLanguageCorrection,
                        cancellationToken: cancellationToken,
                        documentLock: documentLock
                    )
                }
                resultStore.set(result, for: pageNumber)
            }
        }
        queue.waitUntilAllOperationsAreFinished()

        let results = (startPage...endPage).map { pageNumber in
            resultStore.get(pageNumber) ?? cancelledPage(pageNumber: pageNumber)
        }
        let wasCancelled = results.contains { $0["status"] as? String == "cancelled" }

        return PdfPageRangeResult(
            pageCount: document.pageCount,
            startPage: startPage,
            endPage: endPage,
            pages: results,
            cancelled: wasCancelled
        )
    }

    private static func recognizePage(
        document: PDFDocument,
        pageNumber: Int,
        languages: [String],
        mode: RecognitionMode,
        automaticallyDetectsLanguage: Bool?,
        usesLanguageCorrection: Bool?,
        cancellationToken: PdfCancellationToken?,
        documentLock: NSLock
    ) -> [String: Any] {
        if cancellationToken?.isCancelled == true {
            return cancelledPage(pageNumber: pageNumber)
        }

        documentLock.lock()
        var documentIsLocked = true
        defer {
            if documentIsLocked {
                documentLock.unlock()
            }
        }

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
            documentLock.unlock()
            documentIsLocked = false

            if cancellationToken?.isCancelled == true {
                return cancelledPage(pageNumber: pageNumber)
            }
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

    private static func cancelledPage(pageNumber: Int) -> [String: Any] {
        [
            "page": pageNumber,
            "text": "",
            "status": "cancelled",
            "source": "vision",
            "error": [
                "code": "CANCELLED",
                "message": "PDF page recognition was cancelled"
            ]
        ]
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

    static func loadDocument(at url: URL) throws -> PDFDocument {
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
        case "DOCUMENT_LOAD_FAILED", "OCR_FAILED", "FILE_NOT_FOUND", "INVALID_OPTIONS", "CANCELLED":
            return domain
        default:
            return "OCR_FAILED"
        }
    }

    private static func makeError(domain: String, message: String) -> NSError {
        NSError(domain: domain, code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

final class PdfCancellationToken {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

private final class PdfPageResultStore {
    private let lock = NSLock()
    private var results: [Int: [String: Any]] = [:]

    func set(_ result: [String: Any], for pageNumber: Int) {
        lock.lock()
        results[pageNumber] = result
        lock.unlock()
    }

    func get(_ pageNumber: Int) -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        return results[pageNumber]
    }
}
