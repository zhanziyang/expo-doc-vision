# expo-doc-vision

Expo native module for **offline document text extraction** on iOS.

> ⚠️ **iOS only** — Android is not supported yet
> ⚠️ **Requires Expo Dev Client or Bare Workflow** — Not compatible with Expo Go
> ⚠️ **Fully offline** — No network requests, no third-party SDKs
> ⚠️ **No data leaves the device** — Privacy-first design

## Features

- 🚀 **Blazing fast** — Native on-device processing with hardware acceleration
- 📄 **PDF support** — Extract text from both text-based and scanned PDFs
- 🖼️ **Image OCR** — Recognize text in JPG, PNG, and HEIC images
- 📝 **DOCX extraction** — Fast offline text extraction from Word documents
- 📃 **TXT support** — Read plain text files with automatic encoding detection
- 🔒 **Privacy-first** — All processing happens on-device, no data leaves your phone
- 🌐 **Multi-language** — Support for 18+ languages with auto-detection (iOS 16+)
- ⚡ **Fast & Accurate modes** — Choose between speed and precision

## Installation

```bash
npx expo install expo-doc-vision
```

Or with npm/yarn:

```bash
npm install expo-doc-vision
# or
yarn add expo-doc-vision
```

## iOS Requirements

- **iOS 13.0+** (minimum supported version)
- **Expo SDK 50+** (or React Native 0.73+)
- **Expo Dev Client** or **Bare Workflow**

### iOS Version Compatibility

| iOS Version | Features |
|-------------|----------|
| **iOS 13-14** | Basic OCR, PDF text extraction, English only (en-US) |
| **iOS 15** | Multi-language support (18+ languages) |
| **iOS 16+** | Auto language detection, improved accuracy |

> **Note:** `automaticallyDetectsLanguage` and `usesLanguageCorrection` options require iOS 16+. On older versions, these options are ignored gracefully.

### Setup with Expo Dev Client

Add the plugin to your `app.json` or `app.config.js`:

```json
{
  "expo": {
    "plugins": ["expo-doc-vision"]
  }
}
```

Then rebuild your development client:

```bash
npx expo prebuild
npx expo run:ios
```

## Usage

### Basic Usage

```typescript
import { recognize } from 'expo-doc-vision';

// Recognize text from an image
const result = await recognize({
  uri: 'file:///path/to/image.jpg',
});

console.log(result.text);
// => "Hello, World!"
```

### PDF Documents

```typescript
import { recognize } from 'expo-doc-vision';

// Recognize text from a PDF
const result = await recognize({
  uri: 'file:///path/to/document.pdf',
});

console.log(result.text);
// => Full text from all pages

console.log(result.pages);
// => [{ page: 1, text: "Page 1 content..." }, ...]

console.log(result.source);
// => "pdf-text" (text-based PDF) or "vision" (scanned PDF)
```

### With Options

```typescript
import { recognize } from 'expo-doc-vision';

const result = await recognize({
  uri: 'file:///path/to/document.pdf',
  type: 'auto',              // 'auto' | 'pdf' | 'image'
  mode: 'accurate',          // 'fast' | 'accurate'
  language: ['en-US', 'zh-Hans'], // BCP 47 language codes
});
```

## API Reference

### `recognize(options: RecognizeOptions): Promise<OcrResult>`

Performs OCR on a document (image or PDF).

#### RecognizeOptions

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `uri` | `string` | *required* | URI of the document (file://, content://, or absolute path) |
| `type` | `'auto' \| 'pdf' \| 'image'` | `'auto'` | Document type (auto-detected from extension) |
| `mode` | `'fast' \| 'accurate'` | `'accurate'` | Recognition mode |
| `language` | `string[]` | `[]` | Recognition languages (BCP 47 codes) |
| `automaticallyDetectsLanguage` | `boolean` | `true` | Auto-detect language (iOS 16+) |
| `usesLanguageCorrection` | `boolean` | `true` | Apply language-specific corrections |

#### OcrResult

| Property | Type | Description |
|----------|------|-------------|
| `text` | `string` | Full concatenated text from all pages |
| `pages` | `OcrPageResult[]` | Per-page results (only for multi-page documents) |
| `source` | `'vision' \| 'pdf-text' \| 'docx-xml' \| 'txt'` | Source of text extraction |

#### OcrPageResult

| Property | Type | Description |
|----------|------|-------------|
| `page` | `number` | Page number (1-indexed) |
| `text` | `string` | Recognized text from this page |

### Error Handling

```typescript
import { recognize, ExpoDocVisionError, ExpoDocVisionErrorCode } from 'expo-doc-vision';

try {
  const result = await recognize({ uri: 'file:///invalid/path.pdf' });
} catch (error) {
  if (error instanceof ExpoDocVisionError) {
    switch (error.code) {
      case ExpoDocVisionErrorCode.FILE_NOT_FOUND:
        console.error('File not found');
        break;
      case ExpoDocVisionErrorCode.UNSUPPORTED_FILE_TYPE:
        console.error('Unsupported file type');
        break;
      case ExpoDocVisionErrorCode.DOCUMENT_LOAD_FAILED:
        console.error('Failed to load document');
        break;
      case ExpoDocVisionErrorCode.OCR_FAILED:
        console.error('OCR processing failed');
        break;
      case ExpoDocVisionErrorCode.PLATFORM_NOT_SUPPORTED:
        console.error('Platform not supported (iOS only)');
        break;
    }
  }
}
```

## Supported File Types

| Type | Extensions | Strategy |
|------|------------|----------|
| Image | `.jpg`, `.jpeg`, `.png`, `.heic`, `.heif` | Apple Vision OCR |
| PDF (text-based) | `.pdf` | PDFKit text extraction |
| PDF (scanned) | `.pdf` | PDFKit → render → Vision OCR |
| DOCX | `.docx` | Offline XML extraction (no OCR) |
| TXT | `.txt` | Direct read with encoding detection |

## Limitations

- **iOS only** — Android support is planned for future releases
- **No bounding boxes** — Only text content is returned
- **No streaming** — Results are returned all at once
- **No handwriting** — Optimized for printed text
- **No .doc support** — Legacy Word binary format (`.doc`) cannot be parsed offline; convert to `.docx` or `.pdf`

## How It Works

### PDF Processing

1. Load PDF using `PDFDocument`
2. Try to extract text using `PDFDocument.string`
3. If text length > 20 characters → return as text-based PDF
4. Otherwise → render each page to image → run Vision OCR

### Image Processing

1. Load image using `CGImageSource`
2. Run `VNRecognizeTextRequest` with specified options
3. Return concatenated text from all observations

### DOCX Processing

1. Read DOCX file as ZIP archive (DOCX is a ZIP container)
2. Extract `word/document.xml` from the archive
3. Parse XML and extract text from `<w:t>` elements
4. Return plain text (no OCR needed, significantly faster)

### TXT Processing

1. Read file as raw bytes
2. Detect encoding via BOM (Byte Order Mark) if present
3. Try encodings in order: UTF-8, UTF-16, then legacy encodings
4. Supported encodings: UTF-8, UTF-16, UTF-32, GB18030, GBK, GB2312, Big5, Shift-JIS, EUC-JP, EUC-KR, Windows-1252, ISO-8859-1

## Roadmap

- [ ] Android support (ML Kit)
- [ ] Bounding box coordinates
- [ ] Progress callbacks
- [ ] Confidence scores
- [ ] Page rotation detection

## License

MIT © [zhanziyang](https://github.com/zhanziyang)

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.
