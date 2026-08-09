import { requireNativeModule } from "expo-modules-core";

import type {
  OcrResult,
  PdfInfo,
  PdfPageRangeResult,
  RecognizeOptions,
  RecognizePdfPagesOptions,
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
};

// This will automatically load the native module using Expo's module system.
export default requireNativeModule<NativeExpoDocVisionModule>("ExpoDocVision");
