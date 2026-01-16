import Foundation

/// Extracts text from plain text files with automatic encoding detection.
enum TxtTextExtractor {

    /// Extracts text content from a plain text file.
    /// - Parameter url: File URL to the text file
    /// - Returns: Text content with detected encoding
    /// - Throws: NSError if extraction fails
    static func extractText(from url: URL) throws -> String {
        // Read raw file data
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw NSError(
                domain: "FILE_NOT_FOUND",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to read file: \(error.localizedDescription)"]
            )
        }

        // Handle empty file
        if data.isEmpty {
            return ""
        }

        // Decode with encoding detection
        guard let text = decodeTextData(data) else {
            throw NSError(
                domain: "DOCUMENT_LOAD_FAILED",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to decode text file - unsupported encoding"]
            )
        }

        return text
    }

    // MARK: - Encoding Detection

    /// Decodes text data by detecting encoding from BOM or trying common encodings.
    /// Uses validation for UTF-8 and legacy encodings to ensure correct detection.
    private static func decodeTextData(_ data: Data) -> String? {
        return EncodingUtils.decodeData(data, validateUtf8: true, validateLegacy: true)
    }
}
