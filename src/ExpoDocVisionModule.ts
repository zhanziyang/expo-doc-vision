import { requireNativeModule } from "expo-modules-core";

import type {
  OcrResult,
  PdfInfo,
  PdfOcrSession,
  PdfPageRangeResult,
  RecognizeOptions,
  RecognizePdfPagesOptions,
  RecognizePdfSessionPagesOptions,
} from "./types";

type NativeExpoDocVisionModule = {
  recognize(
    options: Required<
      Pick<RecognizeOptions, "uri" | "type" | "language" | "mode">
    > &
      RecognizeOptions,
  ): Promise<OcrResult>;
  getPdfInfo(uri: string): Promise<PdfInfo>;
  recognizePdfPages(
    options: RecognizePdfPagesOptions,
  ): Promise<PdfPageRangeResult>;
  createPdfOcrSession(uri: string): Promise<PdfOcrSession>;
  recognizePdfSessionPages(
    options: RecognizePdfSessionPagesOptions,
  ): Promise<PdfPageRangeResult>;
  cancelPdfOcrSession(sessionId: string): Promise<void>;
  closePdfOcrSession(sessionId: string): Promise<void>;
};

// This will automatically load the native module using Expo's module system.
export default requireNativeModule<NativeExpoDocVisionModule>("ExpoDocVision");
