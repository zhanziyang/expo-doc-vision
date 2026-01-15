import ExpoModulesCore

/// Expo Module for document OCR using Apple Vision and PDFKit.
public class ExpoDocVisionModule: Module {

    public func definition() -> ModuleDefinition {
        Name("ExpoDocVision")

        AsyncFunction("recognize") { (options: [String: Any], promise: Promise) in
            self.handleRecognize(options: options, promise: promise)
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

        // Determine document type
        let documentType: DocumentType
        if typeString == "auto" {
            documentType = Utils.detectDocumentType(from: fileUrl)
        } else if typeString == "pdf" {
            documentType = .pdf
        } else if typeString == "image" {
            documentType = .image
        } else {
            documentType = Utils.detectDocumentType(from: fileUrl)
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

                case .unknown:
                    promise.reject(
                        "UNSUPPORTED_FILE_TYPE",
                        "Unsupported file type: \(fileUrl.pathExtension)"
                    )
                    return
                }

                DispatchQueue.main.async {
                    promise.resolve(result)
                }

            } catch let error as NSError {
                DispatchQueue.main.async {
                    promise.reject(error.domain, error.localizedDescription)
                }
            } catch {
                DispatchQueue.main.async {
                    promise.reject("OCR_FAILED", error.localizedDescription)
                }
            }
        }
    }
}
