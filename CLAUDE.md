# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

expo-doc-vision is an Expo native module providing offline document OCR for iOS. It uses Apple's Vision and PDFKit frameworks for privacy-first, on-device text extraction from images and PDFs.

## Build Commands

```bash
npm run build          # Build TypeScript (src/ and plugin/)
npm run clean          # Clean build artifacts
npm run lint           # Run ESLint
npm run test           # Run tests
npm run prepare        # Prepare module for publishing
```

## Architecture

**Three-layer structure:**

1. **TypeScript API (`src/`)** - Public interface exposing `recognize()` function, handles platform validation and option normalization before calling native code

2. **Config Plugin (`plugin/`)** - Expo config plugin (`withExpoDocVision.ts`) that sets iOS deployment target to 13.0

3. **Native iOS (`ios/`)** - Swift implementation:
   - `ExpoDocVisionModule.swift` - Expo module entry point, async function handler
   - `ImageRecognizer.swift` - Vision framework OCR for images
   - `PdfRecognizer.swift` - PDF text extraction (native text layer or image-based OCR)
   - `Utils.swift` - Shared enums and utilities

**Document Processing Flow:**
- PDFs: Check for text layer (>20 chars) → extract directly OR render pages to images for OCR
- Images: Load via CGImageSource → run VNRecognizeTextRequest
- iOS 16+: Uses VNRecognizeTextRequestRevision3 for better accuracy

## Key Files

- `src/index.ts` - Main export, `recognize()` function implementation
- `src/types.ts` - TypeScript interfaces (`RecognizeOptions`, `RecognizeResult`)
- `src/errors.ts` - Error codes and `ExpoDocVisionError` class
- `ios/ExpoDocVisionModule.swift` - Native module definition
- `expo-module.config.json` - Expo module platform configuration

## Error Handling

Uses `ExpoDocVisionError` with codes: `FILE_NOT_FOUND`, `UNSUPPORTED_FILE_TYPE`, `DOCUMENT_LOAD_FAILED`, `OCR_FAILED`, `INVALID_OPTIONS`, `PLATFORM_NOT_SUPPORTED`

## Platform Requirements

- iOS 13.0+ only (no Android support)
- Expo SDK 50+
- Native frameworks: Vision, PDFKit, UIKit, CoreGraphics

## iOS Version Compatibility

| iOS Version | Features |
|-------------|----------|
| **iOS 13.0+** | Basic OCR, PDF text extraction, fast/accurate modes |
| **iOS 15.0+** | Multi-language support (all supported languages) |
| **iOS 16.0+** | `automaticallyDetectsLanguage`, `VNRecognizeTextRequestRevision3` for better accuracy |

**Fallback behavior:**
- iOS 13-14: English only (en-US default)
- iOS 15: All languages, but no auto-detection
- iOS 16+: Full feature support with auto language detection
