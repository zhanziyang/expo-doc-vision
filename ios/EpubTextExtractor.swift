import Foundation
import ZIPFoundation

/// Extracts text from EPUB files without using OCR.
/// EPUB files are ZIP archives containing HTML/XHTML content.
enum EpubTextExtractor {

    private struct ManifestItem {
        let href: String
        let mediaType: String
    }

    /// Extracts all text content from an EPUB file.
    /// - Parameter url: File URL to the EPUB document
    /// - Returns: Plain text content extracted from the EPUB
    /// - Throws: NSError if extraction fails
    static func extractText(from url: URL) throws -> String {
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw NSError(
                domain: "DOCUMENT_LOAD_FAILED",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to open EPUB file as ZIP archive"]
            )
        }

        guard let containerEntry = archive["META-INF/container.xml"] else {
            throw NSError(
                domain: "DOCUMENT_LOAD_FAILED",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "EPUB file does not contain META-INF/container.xml"]
            )
        }

        let containerXml = try extractXml(from: archive, entry: containerEntry)
        guard let opfPath = parseRootfilePath(containerXml) else {
            throw NSError(
                domain: "DOCUMENT_LOAD_FAILED",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to locate EPUB package document"]
            )
        }

        guard let opfEntry = archive[opfPath] else {
            throw NSError(
                domain: "DOCUMENT_LOAD_FAILED",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "EPUB package document not found at \(opfPath)"]
            )
        }

        let opfXml = try extractXml(from: archive, entry: opfEntry)
        let manifest = parseManifest(opfXml)
        let spine = parseSpine(opfXml)
        var contentPaths = resolveSpine(spine, manifest: manifest, opfPath: opfPath)

        if contentPaths.isEmpty {
            contentPaths = fallbackContentPaths(manifest: manifest, archive: archive, opfPath: opfPath)
        }

        if contentPaths.isEmpty {
            throw NSError(
                domain: "DOCUMENT_LOAD_FAILED",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "No readable content found in EPUB"]
            )
        }

        var extractedParts: [String] = []
        for path in contentPaths {
            guard let entry = archive[path] else { continue }
            let html = try extractXml(from: archive, entry: entry)
            let text = htmlToText(html)
            if !text.isEmpty {
                extractedParts.append(text)
            }
        }

        return extractedParts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - EPUB Parsing

    private static func extractXml(from archive: Archive, entry: Entry) throws -> String {
        var data = Data()
        do {
            _ = try archive.extract(entry) { chunk in
                data.append(chunk)
            }
        } catch {
            throw NSError(
                domain: "DOCUMENT_LOAD_FAILED",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to extract EPUB content: \(error.localizedDescription)"]
            )
        }

        guard let xml = EncodingUtils.decodeData(data, validateUtf8: false, validateLegacy: false) else {
            throw NSError(
                domain: "DOCUMENT_LOAD_FAILED",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to decode EPUB content - unsupported encoding"]
            )
        }

        return xml
    }

    private static func parseRootfilePath(_ xml: String) -> String? {
        return extractFirstAttributeValue(from: xml, element: "rootfile", attribute: "full-path")
    }

    private static func parseManifest(_ xml: String) -> [String: ManifestItem] {
        var items: [String: ManifestItem] = [:]
        let pattern = "<item\\b[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return items
        }

        let nsXml = xml as NSString
        let matches = regex.matches(in: xml, options: [], range: NSRange(location: 0, length: nsXml.length))
        for match in matches {
            guard let range = Range(match.range, in: xml) else { continue }
            let element = String(xml[range])
            guard let id = extractAttributeValue(in: element, name: "id"),
                  let href = extractAttributeValue(in: element, name: "href"),
                  let mediaType = extractAttributeValue(in: element, name: "media-type") else {
                continue
            }
            items[id] = ManifestItem(href: href, mediaType: mediaType)
        }
        return items
    }

    private static func parseSpine(_ xml: String) -> [String] {
        let pattern = "<itemref\\b[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsXml = xml as NSString
        let matches = regex.matches(in: xml, options: [], range: NSRange(location: 0, length: nsXml.length))
        var spine: [String] = []
        for match in matches {
            guard let range = Range(match.range, in: xml) else { continue }
            let element = String(xml[range])
            if let idref = extractAttributeValue(in: element, name: "idref") {
                spine.append(idref)
            }
        }
        return spine
    }

    private static func resolveSpine(
        _ spine: [String],
        manifest: [String: ManifestItem],
        opfPath: String
    ) -> [String] {
        var paths: [String] = []
        for idref in spine {
            guard let item = manifest[idref] else { continue }
            if isReadableMediaType(item.mediaType) {
                paths.append(resolveHref(item.href, opfPath: opfPath))
            }
        }
        return paths
    }

    private static func fallbackContentPaths(
        manifest: [String: ManifestItem],
        archive: Archive,
        opfPath: String
    ) -> [String] {
        let readableItems = manifest.values
            .filter { isReadableMediaType($0.mediaType) }
            .map { resolveHref($0.href, opfPath: opfPath) }

        if !readableItems.isEmpty {
            return readableItems
        }

        var fallback: [String] = []
        for entry in archive {
            let lowercased = entry.path.lowercased()
            if lowercased.hasSuffix(".xhtml") || lowercased.hasSuffix(".html") || lowercased.hasSuffix(".htm") {
                fallback.append(entry.path)
            }
        }
        return fallback.sorted()
    }

    private static func resolveHref(_ href: String, opfPath: String) -> String {
        let cleanedHref = String(href.split(separator: "#").first ?? Substring(href))
        let decodedHref = cleanedHref.removingPercentEncoding ?? cleanedHref
        let opfDir = (opfPath as NSString).deletingLastPathComponent
        let resolved = URL(fileURLWithPath: opfDir)
            .appendingPathComponent(decodedHref)
            .standardizedFileURL
            .path
        if resolved.hasPrefix("/") {
            return String(resolved.dropFirst())
        }
        return resolved
    }

    private static func isReadableMediaType(_ mediaType: String) -> Bool {
        let normalized = mediaType.lowercased().split(separator: ";").first?.trimmingCharacters(in: .whitespaces) ?? ""
        return normalized == "application/xhtml+xml" ||
            normalized == "application/x-dtbook+xml" ||
            normalized == "text/html"
    }

    private static func extractAttributeValue(in element: String, name: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*\"([^\"]+)\"|\\b\(name)\\s*=\\s*'([^']+)'"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let nsElement = element as NSString
        let range = NSRange(location: 0, length: nsElement.length)
        guard let match = regex.firstMatch(in: element, options: [], range: range) else {
            return nil
        }
        if match.numberOfRanges > 1,
           let valueRange = Range(match.range(at: 1), in: element) {
            return String(element[valueRange])
        }
        if match.numberOfRanges > 2,
           let valueRange = Range(match.range(at: 2), in: element) {
            return String(element[valueRange])
        }
        return nil
    }

    private static func extractFirstAttributeValue(from xml: String, element: String, attribute: String) -> String? {
        let pattern = "<\(element)\\b[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let nsXml = xml as NSString
        let matches = regex.matches(in: xml, options: [], range: NSRange(location: 0, length: nsXml.length))
        for match in matches {
            guard let range = Range(match.range, in: xml) else { continue }
            let elementString = String(xml[range])
            if let value = extractAttributeValue(in: elementString, name: attribute) {
                return value
            }
        }
        return nil
    }

    // MARK: - HTML Text Extraction

    private static func htmlToText(_ html: String) -> String {
        var text = html
        text = text.replacingOccurrences(
            of: "<(script|style)\\b[^>]*>[\\s\\S]*?</\\1>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(
            of: "</(p|div|h[1-6]|li|section|article|header|footer)>",
            with: "\n\n",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "</(tr|table)>",
            with: "\n\n",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "</(td|th)>",
            with: "\t",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = decodeHtmlEntities(text)
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "[ \\t\\u00A0]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHtmlEntities(_ text: String) -> String {
        var result = text
        // Basic XML entities
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        // Typographic quotes
        result = result.replacingOccurrences(of: "&ldquo;", with: "\u{201C}")
        result = result.replacingOccurrences(of: "&rdquo;", with: "\u{201D}")
        result = result.replacingOccurrences(of: "&lsquo;", with: "\u{2018}")
        result = result.replacingOccurrences(of: "&rsquo;", with: "\u{2019}")
        // Dashes and ellipsis
        result = result.replacingOccurrences(of: "&mdash;", with: "\u{2014}")
        result = result.replacingOccurrences(of: "&ndash;", with: "\u{2013}")
        result = result.replacingOccurrences(of: "&hellip;", with: "\u{2026}")
        // Other common entities
        result = result.replacingOccurrences(of: "&copy;", with: "\u{00A9}")
        result = result.replacingOccurrences(of: "&reg;", with: "\u{00AE}")
        result = result.replacingOccurrences(of: "&trade;", with: "\u{2122}")
        result = result.replacingOccurrences(of: "&bull;", with: "\u{2022}")
        result = result.replacingOccurrences(of: "&middot;", with: "\u{00B7}")

        let pattern = "&#(x?[0-9A-Fa-f]+);"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return result
        }

        let nsText = result as NSString
        let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsText.length))
        if matches.isEmpty { return result }

        var output = ""
        var lastIndex = result.startIndex

        for match in matches {
            guard let range = Range(match.range, in: result) else { continue }
            output += result[lastIndex..<range.lowerBound]

            if match.numberOfRanges > 1,
               let valueRange = Range(match.range(at: 1), in: result) {
                let value = String(result[valueRange])
                let scalar: UnicodeScalar?
                if value.lowercased().hasPrefix("x") {
                    let hex = value.dropFirst()
                    if let code = UInt32(hex, radix: 16) {
                        scalar = UnicodeScalar(code)
                    } else {
                        scalar = nil
                    }
                } else if let code = UInt32(value, radix: 10) {
                    scalar = UnicodeScalar(code)
                } else {
                    scalar = nil
                }
                if let scalar = scalar {
                    output.append(Character(scalar))
                }
            }

            lastIndex = range.upperBound
        }

        output += result[lastIndex...]
        return output
    }
}
