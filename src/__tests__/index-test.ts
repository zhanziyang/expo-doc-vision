import { Platform } from "react-native";

import ExpoDocVisionModule from "../ExpoDocVisionModule";
import {
  ExpoDocVisionError,
  ExpoDocVisionErrorCode,
  getPdfInfo,
  recognize,
  recognizePdfPages,
} from "../index";

jest.mock("react-native", () => ({ Platform: { OS: "ios" } }));

jest.mock("../ExpoDocVisionModule", () => ({
  __esModule: true,
  default: {
    recognize: jest.fn(),
    getPdfInfo: jest.fn(),
    recognizePdfPages: jest.fn(),
  },
}));

const nativeModule = ExpoDocVisionModule as jest.Mocked<
  typeof ExpoDocVisionModule
>;

describe("expo-doc-vision API", () => {
  beforeEach(() => {
    jest.resetAllMocks();
    Object.defineProperty(Platform, "OS", { configurable: true, value: "ios" });
  });

  it("normalizes recognize defaults", async () => {
    nativeModule.recognize.mockResolvedValue({
      text: "text",
      source: "vision",
    });

    await recognize({ uri: "file:///image.jpg" });

    expect(nativeModule.recognize).toHaveBeenCalledWith({
      uri: "file:///image.jpg",
      type: "auto",
      language: [],
      mode: "accurate",
      automaticallyDetectsLanguage: undefined,
      usesLanguageCorrection: undefined,
    });
  });

  it("passes normalized PDF range options", async () => {
    nativeModule.recognizePdfPages.mockResolvedValue({
      pageCount: 10,
      startPage: 2,
      endPage: 4,
      pages: [],
    });

    await recognizePdfPages({
      uri: "file:///book.pdf",
      startPage: 2,
      endPage: 4,
    });

    expect(nativeModule.recognizePdfPages).toHaveBeenCalledWith({
      uri: "file:///book.pdf",
      startPage: 2,
      endPage: 4,
      language: [],
      mode: "accurate",
    });
  });

  it.each([
    [{ uri: "file:///book.pdf", startPage: 0, endPage: 1 }, "Page range"],
    [{ uri: "file:///book.pdf", startPage: 3, endPage: 2 }, "Page range"],
    [
      { uri: "file:///book.pdf", startPage: 1.5, endPage: 2 },
      "must be integers",
    ],
  ])("rejects invalid page ranges", async (options, message) => {
    await expect(recognizePdfPages(options)).rejects.toMatchObject({
      code: ExpoDocVisionErrorCode.INVALID_OPTIONS,
      message: expect.stringContaining(message),
    });
    expect(nativeModule.recognizePdfPages).not.toHaveBeenCalled();
  });

  it("rejects unsupported modes before calling native", async () => {
    await expect(
      recognize({
        uri: "file:///image.jpg",
        mode: "slow" as "accurate",
      }),
    ).rejects.toMatchObject({ code: ExpoDocVisionErrorCode.INVALID_OPTIONS });
    expect(nativeModule.recognize).not.toHaveBeenCalled();
  });

  it("rejects non-iOS platforms", async () => {
    Object.defineProperty(Platform, "OS", {
      configurable: true,
      value: "android",
    });

    await expect(getPdfInfo("file:///book.pdf")).rejects.toMatchObject({
      code: ExpoDocVisionErrorCode.PLATFORM_NOT_SUPPORTED,
    });
    expect(nativeModule.getPdfInfo).not.toHaveBeenCalled();
  });

  it("converts native errors to ExpoDocVisionError", async () => {
    nativeModule.getPdfInfo.mockRejectedValue({
      code: "DOCUMENT_LOAD_FAILED",
      message: "Cannot open PDF",
    });

    const promise = getPdfInfo("file:///broken.pdf");
    await expect(promise).rejects.toBeInstanceOf(ExpoDocVisionError);
    await expect(promise).rejects.toMatchObject({
      code: ExpoDocVisionErrorCode.DOCUMENT_LOAD_FAILED,
      message: "Cannot open PDF",
    });
  });

  it("maps unknown native errors to OCR_FAILED", async () => {
    nativeModule.getPdfInfo.mockRejectedValue({
      code: "NATIVE_UNKNOWN",
      message: "Unknown",
    });

    await expect(getPdfInfo("file:///book.pdf")).rejects.toMatchObject({
      code: ExpoDocVisionErrorCode.OCR_FAILED,
      message: "Unknown",
    });
  });
});
