import { Platform } from "react-native";
import ExpoDocVisionModule from "./ExpoDocVisionModule";
import { ExpoDocVisionError, ExpoDocVisionErrorCode } from "./errors";
import type { RecognizeOptions, OcrResult } from "./types";

export * from "./types";
export * from "./errors";

/**
 * Perform OCR on a document (image or PDF).
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
 *   uri: 'file:///path/to/document.pdf',
 *   mode: 'accurate',
 *   language: ['en-US'],
 * });
 *
 * console.log(result.text);
 * ```
 */
export async function recognize(options: RecognizeOptions): Promise<OcrResult> {
  if (Platform.OS !== "ios") {
    throw new ExpoDocVisionError(
      ExpoDocVisionErrorCode.PLATFORM_NOT_SUPPORTED,
      "expo-doc-vision is only supported on iOS"
    );
  }

  if (!options.uri) {
    throw new ExpoDocVisionError(
      ExpoDocVisionErrorCode.INVALID_OPTIONS,
      "URI is required"
    );
  }

  const result = await ExpoDocVisionModule.recognize({
    uri: options.uri,
    type: options.type ?? "auto",
    language: options.language ?? [],
    mode: options.mode ?? "accurate",
    automaticallyDetectsLanguage: options.automaticallyDetectsLanguage,
    usesLanguageCorrection: options.usesLanguageCorrection,
  });

  return result as OcrResult;
}
