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
    private static func decodeTextData(_ data: Data) -> String? {
        // Check for BOM (Byte Order Mark)
        if data.starts(with: [0x00, 0x00, 0xFE, 0xFF]) { // UTF-32 BE
            return String(data: data, encoding: .utf32BigEndian)
        }
        if data.starts(with: [0xFF, 0xFE, 0x00, 0x00]) { // UTF-32 LE
            return String(data: data, encoding: .utf32LittleEndian)
        }
        if data.starts(with: [0xFE, 0xFF]) { // UTF-16 BE
            return String(data: data, encoding: .utf16BigEndian)
        }
        if data.starts(with: [0xFF, 0xFE]) { // UTF-16 LE
            return String(data: data, encoding: .utf16LittleEndian)
        }
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { // UTF-8
            return String(data: data, encoding: .utf8)
        }

        // No BOM - try encodings in order of likelihood
        // UTF-8 first (most common modern encoding)
        if let str = String(data: data, encoding: .utf8), isValidText(str) {
            return str
        }

        // UTF-16 variants
        if let str = String(data: data, encoding: .utf16) {
            return str
        }

        // Try legacy encodings with validation
        return tryLegacyEncodings(data)
    }

    /// Try legacy encodings commonly used for different languages
    private static func tryLegacyEncodings(_ data: Data) -> String? {
        let encodings: [(String.Encoding, String)] = [
            // Chinese encodings
            (String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))), "GB18030"),
            (String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GBK_95.rawValue))), "GBK"),
            (String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_2312_80.rawValue))), "GB2312"),
            (String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.big5.rawValue))), "Big5"),
            // Japanese encodings
            (.shiftJIS, "Shift-JIS"),
            (.japaneseEUC, "EUC-JP"),
            // Korean encoding
            (String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.EUC_KR.rawValue))), "EUC-KR"),
            // Western encodings
            (.windowsCP1252, "Windows-1252"),
            (.isoLatin1, "ISO-8859-1"),
            // ASCII as last resort
            (.ascii, "ASCII")
        ]

        for (encoding, _) in encodings {
            if let str = String(data: data, encoding: encoding), isValidText(str) {
                return str
            }
        }

        return nil
    }

    /// Basic validation to check if decoded text looks reasonable
    private static func isValidText(_ text: String) -> Bool {
        // Empty is valid
        if text.isEmpty { return true }

        // Check for excessive replacement characters (indicates wrong encoding)
        let replacementCount = text.filter { $0 == "\u{FFFD}" }.count
        let threshold = max(1, text.count / 10) // Allow up to 10% replacement chars
        if replacementCount > threshold { return false }

        // Check for excessive null characters
        let nullCount = text.filter { $0 == "\0" }.count
        if nullCount > threshold { return false }

        return true
    }
}
