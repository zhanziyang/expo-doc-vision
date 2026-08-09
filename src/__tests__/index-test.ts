import { Platform } from "react-native";

import ExpoDocVisionModule from "../ExpoDocVisionModule";
import {
  ExpoDocVisionError,
  ExpoDocVisionErrorCode,
  cancelPdfOcrSession,
  closePdfOcrSession,
  createPdfOcrSession,
  getPdfInfo,
  recognize,
  recognizePdfPages,
  recognizePdfSessionPages,
} from "../index";

jest.mock("react-native", () => ({ Platform: { OS: "ios" } }));

jest.mock("../ExpoDocVisionModule", () => ({
  __esModule: true,
  default: {
    recognize: jest.fn(),
    getPdfInfo: jest.fn(),
    recognizePdfPages: jest.fn(),
    createPdfOcrSession: jest.fn(),
    recognizePdfSessionPages: jest.fn(),
    cancelPdfOcrSession: jest.fn(),
    closePdfOcrSession: jest.fn(),
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
      maxConcurrentPages: 2,
    });
  });

  it("passes normalized PDF range options", async () => {
    nativeModule.recognizePdfPages.mockResolvedValue({
      pageCount: 10,
      startPage: 2,
      endPage: 4,
      pages: [],
      cancelled: false,
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
      maxConcurrentPages: 2,
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

  it("opens a PDF session and normalizes session range options", async () => {
    nativeModule.createPdfOcrSession.mockResolvedValue({
      sessionId: "session-1",
      info: {
        pageCount: 362,
        textPageCount: 0,
        scannedPageCount: 362,
        hasTextLayer: false,
      },
    });
    nativeModule.recognizePdfSessionPages.mockResolvedValue({
      pageCount: 362,
      startPage: 1,
      endPage: 5,
      pages: [],
      cancelled: false,
    });

    const session = await createPdfOcrSession("file:///book.pdf");
    await recognizePdfSessionPages({
      sessionId: session.sessionId,
      startPage: 1,
      endPage: 5,
    });

    expect(nativeModule.createPdfOcrSession).toHaveBeenCalledWith(
      "file:///book.pdf",
    );
    expect(nativeModule.recognizePdfSessionPages).toHaveBeenCalledWith({
      sessionId: "session-1",
      startPage: 1,
      endPage: 5,
      language: [],
      mode: "accurate",
      maxConcurrentPages: 2,
    });
  });

  it("cancels and closes sessions through native", async () => {
    nativeModule.cancelPdfOcrSession.mockResolvedValue();
    nativeModule.closePdfOcrSession.mockResolvedValue();

    await cancelPdfOcrSession("session-1");
    await closePdfOcrSession("session-2");

    expect(nativeModule.cancelPdfOcrSession).toHaveBeenCalledWith("session-1");
    expect(nativeModule.closePdfOcrSession).toHaveBeenCalledWith("session-2");
  });

  it("rejects an empty session id before calling native", async () => {
    await expect(
      recognizePdfSessionPages({
        sessionId: "",
        startPage: 1,
        endPage: 2,
      }),
    ).rejects.toMatchObject({ code: ExpoDocVisionErrorCode.INVALID_OPTIONS });
    expect(nativeModule.recognizePdfSessionPages).not.toHaveBeenCalled();
  });

  it("passes an app-configured PDF concurrency limit", async () => {
    nativeModule.recognizePdfPages.mockResolvedValue({
      pageCount: 2,
      startPage: 1,
      endPage: 2,
      pages: [],
    });

    await recognizePdfPages({
      uri: "file:///book.pdf",
      startPage: 1,
      endPage: 2,
      maxConcurrentPages: 1,
    });

    expect(nativeModule.recognizePdfPages).toHaveBeenCalledWith(
      expect.objectContaining({ maxConcurrentPages: 1 }),
    );
  });

  it("rejects an unsafe PDF concurrency limit", async () => {
    await expect(
      recognizePdfPages({
        uri: "file:///book.pdf",
        startPage: 1,
        endPage: 2,
        maxConcurrentPages: 3 as 2,
      }),
    ).rejects.toMatchObject({ code: ExpoDocVisionErrorCode.INVALID_OPTIONS });
    expect(nativeModule.recognizePdfPages).not.toHaveBeenCalled();
  });
});
