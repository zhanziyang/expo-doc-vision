import Foundation
import PDFKit

final class PdfOcrSession {
    let id: String
    let document: PDFDocument
    let info: PdfInfoResult

    private let cancellationToken = PdfCancellationToken()
    private let documentLock = NSLock()
    private let processingLock = NSLock()

    init(document: PDFDocument) {
        self.id = UUID().uuidString
        self.document = document
        self.info = PdfRecognizer.getInfo(document: document)
    }

    func recognizePages(
        startPage: Int,
        endPage: Int,
        languages: [String],
        mode: RecognitionMode,
        automaticallyDetectsLanguage: Bool?,
        usesLanguageCorrection: Bool?,
        maxConcurrentPages: Int
    ) throws -> PdfPageRangeResult {
        processingLock.lock()
        defer { processingLock.unlock() }

        return try PdfRecognizer.recognizePages(
            document: document,
            startPage: startPage,
            endPage: endPage,
            languages: languages,
            mode: mode,
            automaticallyDetectsLanguage: automaticallyDetectsLanguage,
            usesLanguageCorrection: usesLanguageCorrection,
            maxConcurrentPages: maxConcurrentPages,
            cancellationToken: cancellationToken,
            documentLock: documentLock
        )
    }

    func cancel() {
        cancellationToken.cancel()
    }
}

enum PdfOcrSessionManager {
    private static let lock = NSLock()
    private static var sessions: [String: PdfOcrSession] = [:]

    static func create(pdfAt url: URL) throws -> PdfOcrSession {
        let document = try PdfRecognizer.loadDocument(at: url)
        let session = PdfOcrSession(document: document)

        lock.lock()
        sessions[session.id] = session
        lock.unlock()
        return session
    }

    static func get(_ sessionId: String) -> PdfOcrSession? {
        lock.lock()
        defer { lock.unlock() }
        return sessions[sessionId]
    }

    @discardableResult
    static func remove(_ sessionId: String, cancelling: Bool) -> PdfOcrSession? {
        lock.lock()
        let session = sessions.removeValue(forKey: sessionId)
        lock.unlock()

        if cancelling {
            session?.cancel()
        }
        return session
    }

    static func closeAll() {
        lock.lock()
        let activeSessions = Array(sessions.values)
        sessions.removeAll()
        lock.unlock()

        activeSessions.forEach { $0.cancel() }
    }
}
