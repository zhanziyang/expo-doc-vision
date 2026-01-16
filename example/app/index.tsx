import { useState, useMemo, useCallback } from 'react';
import {
  StyleSheet,
  Text,
  View,
  TouchableOpacity,
  ScrollView,
  ActivityIndicator,
  Image,
  Platform,
} from 'react-native';
import * as ImagePicker from 'expo-image-picker';
import * as DocumentPicker from 'expo-document-picker';
import { recognize, RecognizeResult, ExpoDocVisionError } from 'expo-doc-vision';

// Separate component for displaying OCR results with virtualized long text
function ResultDisplay({
  result,
  normalizeText,
  splitIntoChunks,
  showFullText,
  setShowFullText,
  TEXT_PREVIEW_LIMIT,
}: {
  result: RecognizeResult;
  normalizeText: (text: string | undefined) => string;
  splitIntoChunks: (text: string) => string[];
  showFullText: boolean;
  setShowFullText: (show: boolean) => void;
  TEXT_PREVIEW_LIMIT: number;
}) {
  const normalizedText = useMemo(() => normalizeText(result.text), [result.text, normalizeText]);
  const isLongText = normalizedText.length > TEXT_PREVIEW_LIMIT;
  const textChunks = useMemo(
    () => (showFullText ? splitIntoChunks(normalizedText) : []),
    [showFullText, normalizedText, splitIntoChunks]
  );

  return (
    <View style={styles.resultContainer}>
      <Text style={styles.sectionTitle}>Result:</Text>
      <View style={styles.statsContainer}>
        <Text style={styles.statsText}>Source: {result.source}</Text>
        {result.pages && (
          <Text style={styles.statsText}>Pages: {result.pages.length}</Text>
        )}
        <Text style={styles.statsText}>Chars: {normalizedText.length}</Text>
      </View>

      <View style={styles.textBox}>
        {!showFullText ? (
          // Preview mode: show truncated text
          <Text selectable style={styles.resultText}>
            {normalizedText.length > 0
              ? isLongText
                ? normalizedText.slice(0, TEXT_PREVIEW_LIMIT) + '...'
                : normalizedText
              : '(No text detected)'}
          </Text>
        ) : (
          // Full text mode: use nested ScrollView with chunks
          <ScrollView
            style={styles.textScrollContainer}
            nestedScrollEnabled={true}
            showsVerticalScrollIndicator={true}
          >
            {textChunks.map((chunk, index) => (
              <Text key={index} selectable style={styles.resultText}>
                {chunk}
                {index < textChunks.length - 1 ? '\n\n' : ''}
              </Text>
            ))}
          </ScrollView>
        )}
        {isLongText && (
          <TouchableOpacity
            style={styles.showMoreButton}
            onPress={() => setShowFullText(!showFullText)}
          >
            <Text style={styles.showMoreText}>
              {showFullText ? 'Show less' : `Show all (${normalizedText.length} chars)`}
            </Text>
          </TouchableOpacity>
        )}
      </View>
    </View>
  );
}

export default function Index() {
  const [result, setResult] = useState<RecognizeResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [selectedFile, setSelectedFile] = useState<string | null>(null);
  const [mode, setMode] = useState<'fast' | 'accurate'>('accurate');
  const [showFullText, setShowFullText] = useState(false);

  const TEXT_PREVIEW_LIMIT = 1000;
  const CHUNK_SIZE = 500; // Characters per chunk for FlatList

  const clearState = () => {
    setResult(null);
    setError(null);
    setSelectedFile(null);
    setShowFullText(false);
  };

  // Normalize text: remove invisible chars and control chars
  const normalizeText = (text: string | undefined): string => {
    if (!text) return '';
    return text
      .replace(/[\u200B-\u200D\uFEFF\u00AD]/g, '') // Remove zero-width chars
      .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '') // Remove control chars
      .trim();
  };

  // Split text into chunks for virtualized rendering
  const splitIntoChunks = useCallback((text: string): string[] => {
    if (!text) return [];
    const chunks: string[] = [];

    // Try to split by paragraphs first (double newline)
    const paragraphs = text.split(/\n\n+/);

    for (const para of paragraphs) {
      if (para.length <= CHUNK_SIZE) {
        chunks.push(para);
      } else {
        // Split long paragraphs by sentences or fixed size
        let remaining = para;
        while (remaining.length > 0) {
          if (remaining.length <= CHUNK_SIZE) {
            chunks.push(remaining);
            break;
          }
          // Try to break at sentence end or word boundary
          let breakPoint = remaining.lastIndexOf('. ', CHUNK_SIZE);
          if (breakPoint === -1 || breakPoint < CHUNK_SIZE / 2) {
            breakPoint = remaining.lastIndexOf(' ', CHUNK_SIZE);
          }
          if (breakPoint === -1) {
            breakPoint = CHUNK_SIZE;
          }
          chunks.push(remaining.slice(0, breakPoint + 1));
          remaining = remaining.slice(breakPoint + 1);
        }
      }
    }
    return chunks;
  }, []);

  const runOCR = async (uri: string) => {
    setLoading(true);
    setError(null);
    setResult(null);

    try {
      const ocrResult = await recognize({
        uri,
        mode,
        automaticallyDetectsLanguage: true,
        // language: ['en-US'],
      });
      setResult(ocrResult);
    } catch (e) {
      if (e instanceof ExpoDocVisionError) {
        setError(`${e.code}: ${e.message}`);
      } else {
        setError(String(e));
      }
    } finally {
      setLoading(false);
    }
  };

  const pickImage = async () => {
    clearState();

    const permissionResult = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (!permissionResult.granted) {
      setError('Permission to access photos was denied');
      return;
    }

    const pickerResult = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['images'],
      quality: 1,
    });

    if (!pickerResult.canceled && pickerResult.assets[0]) {
      const uri = pickerResult.assets[0].uri;
      setSelectedFile(uri);
      await runOCR(uri);
    }
  };

  const takePhoto = async () => {
    clearState();

    const permissionResult = await ImagePicker.requestCameraPermissionsAsync();
    if (!permissionResult.granted) {
      setError('Permission to access camera was denied');
      return;
    }

    const pickerResult = await ImagePicker.launchCameraAsync({
      quality: 1,
    });

    if (!pickerResult.canceled && pickerResult.assets[0]) {
      const uri = pickerResult.assets[0].uri;
      setSelectedFile(uri);
      await runOCR(uri);
    }
  };

  const pickDocument = async () => {
    clearState();

    const pickerResult = await DocumentPicker.getDocumentAsync({
      type: [
        'application/pdf',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document', // .docx
        'text/plain', // .txt
        'image/*',
      ],
      copyToCacheDirectory: true,
    });

    if (!pickerResult.canceled && pickerResult.assets[0]) {
      const uri = pickerResult.assets[0].uri;
      setSelectedFile(uri);
      await runOCR(uri);
    }
  };

  const fileExtension = selectedFile?.toLowerCase().split('.').pop();
  const isImage = selectedFile && !['pdf', 'docx', 'txt'].includes(fileExtension || '');
  const isDocument = selectedFile && ['pdf', 'docx', 'txt'].includes(fileExtension || '');

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <Text style={styles.title}>expo-doc-vision</Text>
      <Text style={styles.subtitle}>Offline Document OCR</Text>

      {Platform.OS !== 'ios' && (
        <View style={styles.warningBox}>
          <Text style={styles.warningText}>
            This module only works on iOS devices
          </Text>
        </View>
      )}

      <View style={styles.modeSelector}>
        <Text style={styles.modeLabel}>Recognition Mode:</Text>
        <View style={styles.modeButtons}>
          <TouchableOpacity
            style={[styles.modeButton, mode === 'fast' && styles.modeButtonActive]}
            onPress={() => setMode('fast')}
          >
            <Text style={[styles.modeButtonText, mode === 'fast' && styles.modeButtonTextActive]}>
              Fast
            </Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[styles.modeButton, mode === 'accurate' && styles.modeButtonActive]}
            onPress={() => setMode('accurate')}
          >
            <Text style={[styles.modeButtonText, mode === 'accurate' && styles.modeButtonTextActive]}>
              Accurate
            </Text>
          </TouchableOpacity>
        </View>
      </View>

      <View style={styles.buttonContainer}>
        <TouchableOpacity style={styles.button} onPress={pickImage}>
          <Text style={styles.buttonText}>Pick Image</Text>
        </TouchableOpacity>
        <TouchableOpacity style={styles.button} onPress={takePhoto}>
          <Text style={styles.buttonText}>Take Photo</Text>
        </TouchableOpacity>
        <TouchableOpacity style={styles.button} onPress={pickDocument}>
          <Text style={styles.buttonText}>Pick Document</Text>
        </TouchableOpacity>
      </View>

      {loading && (
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="large" color="#007AFF" />
          <Text style={styles.loadingText}>Processing...</Text>
        </View>
      )}

      {selectedFile && isImage && (
        <View style={styles.previewContainer}>
          <Text style={styles.sectionTitle}>Selected Image:</Text>
          <Image source={{ uri: selectedFile }} style={styles.preview} resizeMode="contain" />
        </View>
      )}

      {selectedFile && isDocument && (
        <View style={styles.previewContainer}>
          <Text style={styles.sectionTitle}>Selected Document:</Text>
          <Text style={styles.fileName}>{selectedFile.split('/').pop()}</Text>
        </View>
      )}

      {error && (
        <View style={styles.errorContainer}>
          <Text style={styles.errorTitle}>Error:</Text>
          <Text style={styles.errorText}>{error}</Text>
        </View>
      )}

      {result && <ResultDisplay
        result={result}
        normalizeText={normalizeText}
        splitIntoChunks={splitIntoChunks}
        showFullText={showFullText}
        setShowFullText={setShowFullText}
        TEXT_PREVIEW_LIMIT={TEXT_PREVIEW_LIMIT}
      />}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  content: {
    padding: 20,
    paddingBottom: 40,
  },
  title: {
    fontSize: 28,
    fontWeight: 'bold',
    textAlign: 'center',
    marginBottom: 4,
  },
  subtitle: {
    fontSize: 16,
    color: '#666',
    textAlign: 'center',
    marginBottom: 24,
  },
  warningBox: {
    backgroundColor: '#FFF3CD',
    padding: 12,
    borderRadius: 8,
    marginBottom: 20,
  },
  warningText: {
    color: '#856404',
    textAlign: 'center',
  },
  modeSelector: {
    marginBottom: 20,
  },
  modeLabel: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 8,
  },
  modeButtons: {
    flexDirection: 'row',
    gap: 10,
  },
  modeButton: {
    flex: 1,
    padding: 12,
    borderRadius: 8,
    backgroundColor: '#e0e0e0',
    alignItems: 'center',
  },
  modeButtonActive: {
    backgroundColor: '#007AFF',
  },
  modeButtonText: {
    fontSize: 16,
    color: '#333',
  },
  modeButtonTextActive: {
    color: '#fff',
    fontWeight: '600',
  },
  buttonContainer: {
    flexDirection: 'row',
    gap: 10,
    marginBottom: 20,
  },
  button: {
    flex: 1,
    backgroundColor: '#007AFF',
    padding: 14,
    borderRadius: 8,
    alignItems: 'center',
  },
  buttonText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
  },
  loadingContainer: {
    alignItems: 'center',
    padding: 20,
  },
  loadingText: {
    marginTop: 10,
    fontSize: 16,
    color: '#666',
  },
  previewContainer: {
    marginBottom: 20,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 10,
  },
  preview: {
    width: '100%',
    height: 200,
    borderRadius: 8,
    backgroundColor: '#e0e0e0',
  },
  fileName: {
    fontSize: 14,
    color: '#666',
    padding: 12,
    backgroundColor: '#fff',
    borderRadius: 8,
  },
  errorContainer: {
    backgroundColor: '#FFEBEE',
    padding: 16,
    borderRadius: 8,
    marginBottom: 20,
  },
  errorTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#C62828',
    marginBottom: 4,
  },
  errorText: {
    fontSize: 14,
    color: '#C62828',
  },
  resultContainer: {
    marginTop: 10,
  },
  statsContainer: {
    flexDirection: 'row',
    gap: 20,
    marginBottom: 16,
  },
  statsText: {
    fontSize: 14,
    color: '#666',
  },
  pageContainer: {
    marginBottom: 16,
  },
  pageTitle: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 8,
    color: '#333',
  },
  textBox: {
    backgroundColor: '#fff',
    padding: 16,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#e0e0e0',
  },
  textScrollContainer: {
    maxHeight: 400, // Fixed height for scrollable text area
  },
  resultText: {
    fontSize: 14,
    lineHeight: 22,
    color: '#333',
  },
  showMoreButton: {
    marginTop: 12,
    paddingVertical: 8,
    alignItems: 'center',
    borderTopWidth: 1,
    borderTopColor: '#e0e0e0',
  },
  showMoreText: {
    color: '#007AFF',
    fontSize: 14,
    fontWeight: '600',
  },
});
