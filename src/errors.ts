/**
 * Error codes for expo-doc-vision.
 */
export enum ExpoDocVisionErrorCode {
  /** The specified file was not found. */
  FILE_NOT_FOUND = "FILE_NOT_FOUND",

  /** The file type is not supported. */
  UNSUPPORTED_FILE_TYPE = "UNSUPPORTED_FILE_TYPE",

  /** Failed to load or parse the document. */
  DOCUMENT_LOAD_FAILED = "DOCUMENT_LOAD_FAILED",

  /** OCR processing failed. */
  OCR_FAILED = "OCR_FAILED",

  /** Invalid options provided. */
  INVALID_OPTIONS = "INVALID_OPTIONS",

  /** Platform not supported (Android). */
  PLATFORM_NOT_SUPPORTED = "PLATFORM_NOT_SUPPORTED",
}

/**
 * Custom error class for expo-doc-vision errors.
 */
export class ExpoDocVisionError extends Error {
  code: ExpoDocVisionErrorCode;

  constructor(code: ExpoDocVisionErrorCode, message: string) {
    super(message);
    this.name = "ExpoDocVisionError";
    this.code = code;
  }
}
