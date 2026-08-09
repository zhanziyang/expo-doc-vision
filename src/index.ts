import { Platform } from "react-native";

import ExpoDocVisionModule from "./ExpoDocVisionModule";
import { ExpoDocVisionError, ExpoDocVisionErrorCode } from "./errors";
import type {
  RecognizeOptions,
  OcrResult,
  PdfInfo,
  PdfPageRangeResult,
  RecognizePdfPagesOptions,
} from "./types";

export * from "./types";
export * from "./errors";

/**
 * Perform OCR on a document (image, PDF, or EPUB).
 *
 * @param options - Recognition options including URI and settings
 * @returns Promise resolving to OCR results
 * @throws {ExpoDocVisionError} If recognition fails
 *
 * @example
 * ```typescript
 * import { recognize } from 'expo-doc-vision';
 *
 * const result = await recognize({
 *   uri: 'file:///path/to/book.epub',
 *   mode: 'accurate',
 *   language: ['en-US'],
 * });
 *
 * console.log(result.text);
 * ```
 */
export async function recognize(options: RecognizeOptions): Promise<OcrResult> {
  assertIos();
  validateUri(options?.uri);
  validateType(options.type);
  validateMode(options.mode);

  try {
    return await ExpoDocVisionModule.recognize({
      uri: options.uri,
      type: options.type ?? "auto",
      language: options.language ?? [],
      mode: options.mode ?? "accurate",
      automaticallyDetectsLanguage: options.automaticallyDetectsLanguage,
      usesLanguageCorrection: options.usesLanguageCorrection,
    });
  } catch (error) {
    throw toExpoDocVisionError(error);
  }
}

/** Return page and text-layer metadata for a PDF. */
export async function getPdfInfo(uri: string): Promise<PdfInfo> {
  assertIos();
  validateUri(uri);

  try {
    return await ExpoDocVisionModule.getPdfInfo(uri);
  } catch (error) {
    throw toExpoDocVisionError(error);
  }
}

/** Recognize an inclusive, 1-based range of PDF pages. */
export async function recognizePdfPages(
  options: RecognizePdfPagesOptions,
): Promise<PdfPageRangeResult> {
  assertIos();
  validateUri(options?.uri);
  validateMode(options.mode);

  if (
    !Number.isInteger(options.startPage) ||
    !Number.isInteger(options.endPage)
  ) {
    throw invalidOptions("startPage and endPage must be integers");
  }
  if (options.startPage < 1 || options.endPage < options.startPage) {
    throw invalidOptions("Page range must satisfy 1 <= startPage <= endPage");
  }

  try {
    return await ExpoDocVisionModule.recognizePdfPages({
      ...options,
      language: options.language ?? [],
      mode: options.mode ?? "accurate",
    });
  } catch (error) {
    throw toExpoDocVisionError(error);
  }
}

function assertIos(): void {
  if (Platform.OS !== "ios") {
    throw new ExpoDocVisionError(
      ExpoDocVisionErrorCode.PLATFORM_NOT_SUPPORTED,
      "expo-doc-vision is only supported on iOS",
    );
  }
}

function validateUri(uri: string | undefined): asserts uri is string {
  if (typeof uri !== "string" || uri.trim().length === 0) {
    throw invalidOptions("URI is required");
  }
}

function validateType(type: RecognizeOptions["type"]): void {
  const validTypes = ["auto", "pdf", "image", "docx", "txt", "epub"];
  if (type !== undefined && !validTypes.includes(type)) {
    throw invalidOptions(`Unsupported document type: ${String(type)}`);
  }
}

function validateMode(mode: RecognizeOptions["mode"]): void {
  if (mode !== undefined && mode !== "fast" && mode !== "accurate") {
    throw invalidOptions(`Unsupported recognition mode: ${String(mode)}`);
  }
}

function invalidOptions(message: string): ExpoDocVisionError {
  return new ExpoDocVisionError(
    ExpoDocVisionErrorCode.INVALID_OPTIONS,
    message,
  );
}

function toExpoDocVisionError(error: unknown): ExpoDocVisionError {
  if (error instanceof ExpoDocVisionError) {
    return error;
  }

  const nativeError = error as { code?: unknown; message?: unknown } | null;
  const code =
    typeof nativeError?.code === "string"
      ? nativeError.code.replace(/^ERR_/, "")
      : ExpoDocVisionErrorCode.OCR_FAILED;
  const knownCode = Object.values(ExpoDocVisionErrorCode).includes(
    code as ExpoDocVisionErrorCode,
  )
    ? (code as ExpoDocVisionErrorCode)
    : ExpoDocVisionErrorCode.OCR_FAILED;
  const message =
    typeof nativeError?.message === "string"
      ? nativeError.message
      : "Document recognition failed";

  return new ExpoDocVisionError(knownCode, message);
}
