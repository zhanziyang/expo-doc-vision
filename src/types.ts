/**
 * Options for the OCR recognition request.
 */
export type RecognizeOptions = {
  /**
   * URI of the document to recognize.
   * Supports file:// and absolute paths.
   */
  uri: string;

  /**
   * Type of the document.
   * - "auto": Automatically detect based on file extension (default)
   * - "pdf": Treat as PDF document
   * - "image": Treat as image (jpg, png, heic)
   */
  type?: "auto" | "pdf" | "image";

  /**
   * Recognition languages in order of preference.
   * Uses BCP 47 language tags (e.g., ["en-US", "zh-Hans"]).
   * If not specified, defaults to device language settings.
   */
  language?: string[];

  /**
   * Recognition mode.
   * - "fast": Prioritize speed over accuracy
   * - "accurate": Prioritize accuracy over speed (default)
   */
  mode?: "fast" | "accurate";

  /**
   * Automatically detect the language of the text.
   * When true, Vision will attempt to identify the language automatically.
   * Requires iOS 16+. On older versions, this option is ignored.
   * @default true when language is not specified
   */
  automaticallyDetectsLanguage?: boolean;

  /**
   * Use language correction during recognition.
   * When true, Vision applies language-specific corrections to improve accuracy.
   * @default true
   */
  usesLanguageCorrection?: boolean;
};

/**
 * OCR result for a single page.
 */
export type OcrPageResult = {
  /**
   * Page number (1-indexed).
   */
  page: number;

  /**
   * Recognized text content from this page.
   */
  text: string;
};

/**
 * Result of the OCR recognition.
 */
export type OcrResult = {
  /**
   * Full concatenated text from all pages.
   */
  text: string;

  /**
   * Per-page results. Only present for multi-page documents (PDFs).
   */
  pages?: OcrPageResult[];

  /**
   * Source of the text extraction.
   * - "vision": Text was extracted using Apple Vision OCR
   * - "pdf-text": Text was extracted directly from PDF text layer
   */
  source: "vision" | "pdf-text";
};

/**
 * Alias for OcrResult for API consistency with recognize().
 */
export type RecognizeResult = OcrResult;
