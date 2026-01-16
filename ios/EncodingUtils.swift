import Foundation

/// Shared utilities for text encoding detection and decoding.
enum EncodingUtils {

    // MARK: - BOM Detection

    /// Detects encoding from BOM (Byte Order Mark) and decodes the data.
    /// - Parameter data: Raw data to decode
    /// - Returns: Decoded string if BOM was found and decoding succeeded, nil otherwise
    static func decodeWithBOM(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(4))

        // UTF-32 BE: 00 00 FE FF
        if bytes.count >= 4 && bytes[0] == 0x00 && bytes[1] == 0x00 && bytes[2] == 0xFE && bytes[3] == 0xFF {
            return String(data: data, encoding: .utf32BigEndian)
        }
        // UTF-32 LE: FF FE 00 00
        if bytes.count >= 4 && bytes[0] == 0xFF && bytes[1] == 0xFE && bytes[2] == 0x00 && bytes[3] == 0x00 {
            return String(data: data, encoding: .utf32LittleEndian)
        }
        // UTF-16 BE: FE FF
        if bytes.count >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF {
            return String(data: data, encoding: .utf16BigEndian)
        }
        // UTF-16 LE: FF FE
        if bytes.count >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE {
            return String(data: data, encoding: .utf16LittleEndian)
        }
        // UTF-8 BOM: EF BB BF
        if bytes.count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF {
            return String(data: data, encoding: .utf8)
        }

        return nil
    }

    // MARK: - Encoding Fallback

    /// Common legacy encodings for fallback decoding.
    static let legacyEncodings: [String.Encoding] = [
        // Chinese encodings
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))),  // GB18030
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GBK_95.rawValue))),         // GBK
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_2312_80.rawValue))),     // GB2312
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.big5.rawValue))),           // Big5 (Traditional Chinese)
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.HZ_GB_2312.rawValue))),     // HZ-GB-2312
        // Japanese encodings
        .shiftJIS,
        .japaneseEUC,
        // Korean encoding
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.EUC_KR.rawValue))),
        // Western encodings
        .windowsCP1252,
        .isoLatin1,
        // ASCII as last resort
        .ascii
    ]

    /// Decodes data trying legacy encodings with optional validation.
    /// - Parameters:
    ///   - data: Raw data to decode
    ///   - validate: Whether to validate decoded text (default: false)
    /// - Returns: Decoded string or nil if all encodings fail
    static func decodeWithLegacyEncodings(_ data: Data, validate: Bool = false) -> String? {
        for encoding in legacyEncodings {
            if let str = String(data: data, encoding: encoding) {
                if validate {
                    if isValidText(str) {
                        return str
                    }
                } else {
                    return str
                }
            }
        }
        return nil
    }

    // MARK: - Full Decode

    /// Decodes data by trying BOM detection, then UTF-8/UTF-16, then legacy encodings.
    /// - Parameters:
    ///   - data: Raw data to decode
    ///   - validateUtf8: Whether to validate UTF-8 decoded text (for plain text files)
    ///   - validateLegacy: Whether to validate legacy encoding decoded text
    /// - Returns: Decoded string or nil if all methods fail
    static func decodeData(_ data: Data, validateUtf8: Bool = false, validateLegacy: Bool = false) -> String? {
        // Try BOM detection first
        if let str = decodeWithBOM(data) {
            return str
        }

        // No BOM - try UTF-8 first (most common modern encoding)
        if let str = String(data: data, encoding: .utf8) {
            if validateUtf8 {
                if isValidText(str) {
                    return str
                }
            } else {
                return str
            }
        }

        // Try UTF-16
        if let str = String(data: data, encoding: .utf16) {
            return str
        }

        // Try legacy encodings
        return decodeWithLegacyEncodings(data, validate: validateLegacy)
    }

    // MARK: - Validation

    /// Basic validation to check if decoded text looks reasonable.
    /// - Parameter text: Text to validate
    /// - Returns: true if text appears valid, false if it has too many replacement/null chars
    static func isValidText(_ text: String) -> Bool {
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
