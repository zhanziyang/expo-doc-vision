import Foundation
import UIKit

/// Utility functions for expo-doc-vision.
enum Utils {

    /// Resolves a URI string to a file URL.
    /// Handles file://, content://, and relative paths.
    static func resolveUri(_ uri: String) -> URL? {
        // Handle file:// scheme
        if uri.hasPrefix("file://") {
            return URL(string: uri)
        }

        // Handle absolute path
        if uri.hasPrefix("/") {
            return URL(fileURLWithPath: uri)
        }

        // Try as URL string
        if let url = URL(string: uri) {
            return url
        }

        return nil
    }

    /// Determines the document type from file extension.
    static func detectDocumentType(from url: URL) -> DocumentType {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "pdf":
            return .pdf
        case "jpg", "jpeg", "png", "heic", "heif":
            return .image
        case "docx":
            return .docx
        case "epub":
            return .epub
        case "doc":
            return .legacyDoc
        case "txt":
            return .txt
        default:
            return .unknown
        }
    }

    /// Checks if a file exists at the given URL.
    static func fileExists(at url: URL) -> Bool {
        return FileManager.default.fileExists(atPath: url.path)
    }
}

/// Supported document types.
enum DocumentType {
    case pdf
    case image
    case docx
    case epub
    case legacyDoc
    case txt
    case unknown
}

/// Recognition mode for OCR.
enum RecognitionMode: String {
    case fast
    case accurate
}
