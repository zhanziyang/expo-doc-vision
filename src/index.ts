import { Platform } from "react-native";

import ExpoDocVisionModule from "./ExpoDocVisionModule";
import { ExpoDocVisionError, ExpoDocVisionErrorCode } from "./errors";
import type {
  RecognizeOptions,
  OcrResult,
  PdfInfo,
  PdfOcrSession,
  PdfPageRangeResult,
  RecognizePdfPagesOptions,
  RecognizePdfSessionPagesOptions,
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
  validateMaxConcurrentPages(options.maxConcurrentPages);

  try {
    return await ExpoDocVisionModule.recognize({
      uri: options.uri,
      type: options.type ?? "auto",
      language: options.language ?? [],
      mode: options.mode ?? "accurate",
      automaticallyDetectsLanguage: options.automaticallyDetectsLanguage,
      usesLanguageCorrection: options.usesLanguageCorrection,
      maxConcurrentPages: options.maxConcurrentPages ?? 2,
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
  validatePageRange(options);
  validateMaxConcurrentPages(options.maxConcurrentPages);

  try {
    return await ExpoDocVisionModule.recognizePdfPages({
      ...options,
      language: options.language ?? [],
      mode: options.mode ?? "accurate",
      maxConcurrentPages: options.maxConcurrentPages ?? 2,
    });
  } catch (error) {
    throw toExpoDocVisionError(error);
  }
}

/** Open a PDF once for multiple bounded page-range requests. */
export async function createPdfOcrSession(uri: string): Promise<PdfOcrSession> {
  assertIos();
  validateUri(uri);

  try {
    return await ExpoDocVisionModule.createPdfOcrSession(uri);
  } catch (error) {
    throw toExpoDocVisionError(error);
  }
}

/** Recognize pages using an open PDF session. */
export async function recognizePdfSessionPages(
  options: RecognizePdfSessionPagesOptions,
): Promise<PdfPageRangeResult> {
  assertIos();
  validateSessionId(options?.sessionId);
  validatePageRange(options);
  validateMode(options.mode);
  validateMaxConcurrentPages(options.maxConcurrentPages);

  try {
    return await ExpoDocVisionModule.recognizePdfSessionPages({
      ...options,
      language: options.language ?? [],
      mode: options.mode ?? "accurate",
      maxConcurrentPages: options.maxConcurrentPages ?? 2,
    });
  } catch (error) {
    throw toExpoDocVisionError(error);
  }
}

/** Cancel queued work and release an OCR session. */
export async function cancelPdfOcrSession(sessionId: string): Promise<void> {
  assertIos();
  validateSessionId(sessionId);

  try {
    await ExpoDocVisionModule.cancelPdfOcrSession(sessionId);
  } catch (error) {
    throw toExpoDocVisionError(error);
  }
}

/** Release an OCR session after all requested work has finished. */
export async function closePdfOcrSession(sessionId: string): Promise<void> {
  assertIos();
  validateSessionId(sessionId);

  try {
    await ExpoDocVisionModule.closePdfOcrSession(sessionId);
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

function validateSessionId(
  sessionId: string | undefined,
): asserts sessionId is string {
  if (typeof sessionId !== "string" || sessionId.trim().length === 0) {
    throw invalidOptions("sessionId is required");
  }
}

function validatePageRange(options: {
  startPage: number;
  endPage: number;
}): void {
  if (
    !Number.isInteger(options.startPage) ||
    !Number.isInteger(options.endPage)
  ) {
    throw invalidOptions("startPage and endPage must be integers");
  }
  if (options.startPage < 1 || options.endPage < options.startPage) {
    throw invalidOptions("Page range must satisfy 1 <= startPage <= endPage");
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

function validateMaxConcurrentPages(value: number | undefined): void {
  if (value !== undefined && value !== 1 && value !== 2) {
    throw invalidOptions("maxConcurrentPages must be 1 or 2");
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
