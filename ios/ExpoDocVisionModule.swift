import ExpoModulesCore

/// Expo Module for document OCR using Apple Vision and PDFKit.
public class ExpoDocVisionModule: Module {

    public func definition() -> ModuleDefinition {
        Name("ExpoDocVision")

        AsyncFunction("recognize") { (options: [String: Any], promise: Promise) in
            self.handleRecognize(options: options, promise: promise)
        }

        AsyncFunction("getPdfInfo") { (uri: String, promise: Promise) in
            self.handleGetPdfInfo(uri: uri, promise: promise)
        }

        AsyncFunction("recognizePdfPages") { (options: [String: Any], promise: Promise) in
            self.handleRecognizePdfPages(options: options, promise: promise)
        }
    }

    private func handleRecognize(options: [String: Any], promise: Promise) {
        // Extract options
        guard let uri = options["uri"] as? String else {
            promise.reject("INVALID_OPTIONS", "URI is required")
            return
        }

        let typeString = options["type"] as? String ?? "auto"
        let languages = options["language"] as? [String] ?? []
        let modeString = options["mode"] as? String ?? "accurate"
        let automaticallyDetectsLanguage = options["automaticallyDetectsLanguage"] as? Bool
        let usesLanguageCorrection = options["usesLanguageCorrection"] as? Bool

        guard modeString == "fast" || modeString == "accurate" else {
            promise.reject("INVALID_OPTIONS", "Unsupported recognition mode: \(modeString)")
            return
        }

        // Parse recognition mode
        let mode: RecognitionMode = modeString == "fast" ? .fast : .accurate

        // Resolve URI to file URL
        guard let fileUrl = Utils.resolveUri(uri) else {
            promise.reject("INVALID_OPTIONS", "Invalid URI: \(uri)")
            return
        }

        // Check file exists
        guard Utils.fileExists(at: fileUrl) else {
            promise.reject("FILE_NOT_FOUND", "File not found at: \(fileUrl.path)")
            return
        }

        guard let documentType = Self.parseDocumentType(typeString, fileUrl: fileUrl) else {
            promise.reject("INVALID_OPTIONS", "Unsupported document type: \(typeString)")
            return
        }

        // Perform recognition on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result: [String: Any]

                switch documentType {
                case .pdf:
                    let pdfResult = try PdfRecognizer.recognize(
                        pdfAt: fileUrl,
                        languages: languages,
                        mode: mode,
                        automaticallyDetectsLanguage: automaticallyDetectsLanguage,
                        usesLanguageCorrection: usesLanguageCorrection
                    )
                    result = [
                        "text": pdfResult.text,
                        "pages": pdfResult.pages,
                        "source": pdfResult.source
                    ]

                case .image:
                    let text = try ImageRecognizer.recognize(
                        imageAt: fileUrl,
                        languages: languages,
                        mode: mode,
                        automaticallyDetectsLanguage: automaticallyDetectsLanguage,
                        usesLanguageCorrection: usesLanguageCorrection
                    )
                    result = [
                        "text": text,
                        "source": "vision"
                    ]

                case .docx:
                    let text = try DocxTextExtractor.extractText(from: fileUrl)
                    result = [
                        "text": text,
                        "source": "docx-xml"
                    ]

                case .epub:
                    let text = try EpubTextExtractor.extractText(from: fileUrl)
                    result = [
                        "text": text,
                        "source": "epub-html"
                    ]

                case .txt:
                    let text = try TxtTextExtractor.extractText(from: fileUrl)
                    result = [
                        "text": text,
                        "source": "txt"
                    ]

                case .legacyDoc:
                    DispatchQueue.main.async {
                        promise.reject(
                            "UNSUPPORTED_FILE_TYPE",
                            "DOC format is not supported offline. Please convert to DOCX or PDF."
                        )
                    }
                    return

                case .unknown:
                    DispatchQueue.main.async {
                        promise.reject(
                            "UNSUPPORTED_FILE_TYPE",
                            "Unsupported file type: \(fileUrl.pathExtension)"
                        )
                    }
                    return
                }

                DispatchQueue.main.async {
                    promise.resolve(result)
                }

            } catch let error as NSError {
                DispatchQueue.main.async {
                    let errorCode = Self.mapErrorCode(error.domain)
                    promise.reject(errorCode, error.localizedDescription)
                }
            } catch {
                DispatchQueue.main.async {
                    promise.reject("OCR_FAILED", error.localizedDescription)
                }
            }
        }
    }

    private func handleGetPdfInfo(uri: String, promise: Promise) {
        guard let fileUrl = validateFile(uri: uri, promise: promise) else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try PdfRecognizer.getInfo(pdfAt: fileUrl)
                DispatchQueue.main.async { promise.resolve(result.dictionary) }
            } catch {
                self.reject(error: error, promise: promise)
            }
        }
    }

    private func handleRecognizePdfPages(options: [String: Any], promise: Promise) {
        guard let uri = options["uri"] as? String else {
            promise.reject("INVALID_OPTIONS", "URI is required")
            return
        }
        guard let startPage = options["startPage"] as? Int,
              let endPage = options["endPage"] as? Int else {
            promise.reject("INVALID_OPTIONS", "startPage and endPage must be integers")
            return
        }
        guard let fileUrl = validateFile(uri: uri, promise: promise) else { return }

        let languages = options["language"] as? [String] ?? []
        let modeString = options["mode"] as? String ?? "accurate"
        guard modeString == "fast" || modeString == "accurate" else {
            promise.reject("INVALID_OPTIONS", "Unsupported recognition mode: \(modeString)")
            return
        }
        let mode: RecognitionMode = modeString == "fast" ? .fast : .accurate
        let automaticallyDetectsLanguage = options["automaticallyDetectsLanguage"] as? Bool
        let usesLanguageCorrection = options["usesLanguageCorrection"] as? Bool

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try PdfRecognizer.recognizePages(
                    pdfAt: fileUrl,
                    startPage: startPage,
                    endPage: endPage,
                    languages: languages,
                    mode: mode,
                    automaticallyDetectsLanguage: automaticallyDetectsLanguage,
                    usesLanguageCorrection: usesLanguageCorrection
                )
                DispatchQueue.main.async { promise.resolve(result.dictionary) }
            } catch {
                self.reject(error: error, promise: promise)
            }
        }
    }

    private func validateFile(uri: String, promise: Promise) -> URL? {
        guard let fileUrl = Utils.resolveUri(uri) else {
            promise.reject("INVALID_OPTIONS", "Invalid URI: \(uri)")
            return nil
        }
        guard Utils.fileExists(at: fileUrl) else {
            promise.reject("FILE_NOT_FOUND", "File not found at: \(fileUrl.path)")
            return nil
        }
        return fileUrl
    }

    private func reject(error: Error, promise: Promise) {
        let nsError = error as NSError
        DispatchQueue.main.async {
            promise.reject(Self.mapErrorCode(nsError.domain), nsError.localizedDescription)
        }
    }

    private static func parseDocumentType(_ type: String, fileUrl: URL) -> DocumentType? {
        switch type {
        case "auto": return Utils.detectDocumentType(from: fileUrl)
        case "pdf": return .pdf
        case "image": return .image
        case "docx": return .docx
        case "txt": return .txt
        case "epub": return .epub
        default: return nil
        }
    }

    private static func mapErrorCode(_ domain: String) -> String {
        switch domain {
        case "DOCUMENT_LOAD_FAILED",
             "OCR_FAILED",
             "FILE_NOT_FOUND",
             "UNSUPPORTED_FILE_TYPE",
             "INVALID_OPTIONS":
            return domain
        default:
            return "OCR_FAILED"
        }
    }
}
