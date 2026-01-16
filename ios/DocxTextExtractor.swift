import Foundation
import ZIPFoundation

/// Extracts text from DOCX files without using OCR.
/// DOCX files are ZIP archives containing XML documents.
/// Main text content is stored in word/document.xml as <w:t> nodes.
enum DocxTextExtractor {

    /// Extracts all text content from a DOCX file.
    /// - Parameter url: File URL to the DOCX document
    /// - Returns: Plain text content extracted from the document
    /// - Throws: NSError if extraction fails
    static func extractText(from url: URL) throws -> String {
        // Open DOCX as ZIP archive
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw NSError(
                domain: "DOCUMENT_LOAD_FAILED",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to open DOCX file as ZIP archive"]
            )
        }

        // Find word/document.xml entry
        guard let entry = archive["word/document.xml"] else {
            throw NSError(
                domain: "DOCUMENT_LOAD_FAILED",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "DOCX file does not contain word/document.xml"]
            )
        }

        // Extract document.xml content
        var xmlData = Data()
        do {
            _ = try archive.extract(entry) { data in
                xmlData.append(data)
            }
        } catch {
            throw NSError(
                domain: "DOCUMENT_LOAD_FAILED",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to extract document.xml: \(error.localizedDescription)"]
            )
        }

        // Convert to string with encoding detection
        guard let xmlString = decodeXmlData(xmlData) else {
            throw NSError(
                domain: "DOCUMENT_LOAD_FAILED",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to decode document.xml - unsupported encoding"]
            )
        }

        // Extract text from XML
        return extractTextFromXml(xmlString)
    }

    // MARK: - Encoding Detection

    /// Decodes XML data by detecting encoding from BOM or trying common encodings.
    /// OOXML spec requires UTF-8 or UTF-16, but we try additional encodings as fallback.
    private static func decodeXmlData(_ data: Data) -> String? {
        // For XML/DOCX, we don't need strict validation since the content is structured
        return EncodingUtils.decodeData(data, validateUtf8: false, validateLegacy: false)
    }

    // MARK: - XML Text Extraction

    /// Decodes common XML entities to their character equivalents.
    private static func decodeXmlEntities(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        return result
    }

    /// Extracts text content from DOCX XML.
    /// Text is stored in <w:t> elements within the document.
    /// Note: Uses regex-based extraction which handles most DOCX files correctly.
    /// Nested markup within <w:t> elements is rare but may not be fully captured.
    private static func extractTextFromXml(_ xml: String) -> String {
        var result: [String] = []

        // Pattern to match paragraphs and text within them
        let paragraphPattern = "<w:p[^>]*>.*?</w:p>"
        let textPattern = "<w:t[^>]*>([^<]*)</w:t>"

        guard let paragraphRegex = try? NSRegularExpression(pattern: paragraphPattern, options: .dotMatchesLineSeparators),
              let textRegex = try? NSRegularExpression(pattern: textPattern, options: []) else {
            // Fallback: extract all <w:t> content without paragraph structure
            return extractAllTextTags(from: xml)
        }

        let nsXml = xml as NSString
        let fullRange = NSRange(location: 0, length: nsXml.length)

        // Find all paragraphs
        let paragraphMatches = paragraphRegex.matches(in: xml, options: [], range: fullRange)

        for paragraphMatch in paragraphMatches {
            guard let paragraphRange = Range(paragraphMatch.range, in: xml) else { continue }
            let paragraphContent = String(xml[paragraphRange])

            // Find all text within this paragraph
            let nsParagraph = paragraphContent as NSString
            let paragraphNSRange = NSRange(location: 0, length: nsParagraph.length)
            let textMatches = textRegex.matches(in: paragraphContent, options: [], range: paragraphNSRange)

            var paragraphTexts: [String] = []
            for textMatch in textMatches {
                if textMatch.numberOfRanges > 1,
                   let textRange = Range(textMatch.range(at: 1), in: paragraphContent) {
                    let text = decodeXmlEntities(String(paragraphContent[textRange]))
                    if !text.isEmpty {
                        paragraphTexts.append(text)
                    }
                }
            }

            if !paragraphTexts.isEmpty {
                result.append(paragraphTexts.joined())
            }
        }

        // If no paragraphs found, try direct text extraction
        if result.isEmpty {
            return extractAllTextTags(from: xml)
        }

        return result.joined(separator: "\n")
    }

    /// Fallback: extract all <w:t> tags without paragraph structure
    private static func extractAllTextTags(from xml: String) -> String {
        let pattern = "<w:t[^>]*>([^<]*)</w:t>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return ""
        }

        let nsXml = xml as NSString
        let fullRange = NSRange(location: 0, length: nsXml.length)
        let matches = regex.matches(in: xml, options: [], range: fullRange)

        var texts: [String] = []
        for match in matches {
            if match.numberOfRanges > 1,
               let textRange = Range(match.range(at: 1), in: xml) {
                let text = decodeXmlEntities(String(xml[textRange]))
                if !text.isEmpty {
                    texts.append(text)
                }
            }
        }

        return texts.joined()
    }
}
