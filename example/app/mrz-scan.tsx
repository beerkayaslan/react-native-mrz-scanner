import { useState, useCallback, useEffect } from "react";
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  Alert,
  ActivityIndicator,
} from "react-native";
import { useRouter } from "expo-router";
import { useCameraPermissions } from "expo-camera";
import { parseMRZ, type MRZResult } from "../src/utils/mrzUtils";
import { scanMRZ } from "rn-mrz-scanner";

export default function MRZScanScreen() {
  const router = useRouter();
  const [permission, requestPermission] = useCameraPermissions();
  const [parsedData, setParsedData] = useState<MRZResult | null>(null);
  const [processing, setProcessing] = useState(false);

  useEffect(() => {
    if (!permission?.granted) {
      requestPermission();
    }
  }, []);

  const startNativeMRZScan = useCallback(async () => {
    if (parsedData || processing) return;

    setProcessing(true);
    try {
      const rawMRZ = await scanMRZ();
      const result = parseMRZ(rawMRZ);

      if (result) {
        setParsedData(result);
      } else {
        Alert.alert(
          "Hata",
          "MRZ metni ayrıştırılamadı. Lütfen tekrar deneyin.",
        );
      }
    } catch (error: any) {
      const message = String(error?.message ?? "MRZ tarama iptal edildi.");
      if (!message.toLowerCase().includes("iptal")) {
        Alert.alert("Tarama Hatası", message);
      }
    } finally {
      setProcessing(false);
    }
  }, [parsedData, processing]);

  const handleManualInput = () => {
    Alert.prompt?.(
      "MRZ Giriş",
      "MRZ metnini yapıştırın (2 veya 3 satır):",
      (text: string) => {
        if (!text) return;
        const result = parseMRZ(text);
        if (result) {
          setParsedData(result);
        } else {
          Alert.alert(
            "Hata",
            "MRZ metni ayrıştırılamadı. Lütfen tekrar deneyin.",
          );
        }
      },
      "plain-text",
    );
  };

  const navigateToNFC = () => {
    if (!parsedData) return;
    router.push({
      pathname: "/nfc-read",
      params: {
        serialNumber: parsedData.serialNumber,
        dateOfBirth: parsedData.dateOfBirth,
        expiryDate: parsedData.expiryDate,
        firstName: parsedData.firstName,
        lastName: parsedData.lastName,
      },
    });
  };

  const resetScan = () => {
    setParsedData(null);
    setProcessing(false);
  };

  if (!permission?.granted) {
    return (
      <View style={styles.centered}>
        <Text style={styles.message}>
          Kamera izni gereklidir. Lütfen ayarlardan kamera iznini etkinleştirin.
        </Text>
        <TouchableOpacity style={styles.button} onPress={requestPermission}>
          <Text style={styles.buttonText}>İzin Ver</Text>
        </TouchableOpacity>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      {!parsedData ? (
        <View style={styles.scanContainer}>
          <View style={styles.infoBox}>
            <Text style={styles.infoIcon}>📄</Text>
            <Text style={styles.infoText}>
              Lütfen kimliğin arka tarafını kameraya okutunuz. MRZ alanı
              otomatik olarak tanınacaktır.
            </Text>
          </View>

          <View style={styles.actions}>
            <TouchableOpacity
              style={[styles.button, processing && styles.disabledButton]}
              onPress={startNativeMRZScan}
              disabled={processing}
            >
              {processing ? (
                <View style={styles.processingInline}>
                  <ActivityIndicator color="#fff" />
                  <Text style={styles.buttonText}> Taranıyor...</Text>
                </View>
              ) : (
                <Text style={styles.buttonText}>📸 Kamerayı Aç</Text>
              )}
            </TouchableOpacity>

            <TouchableOpacity
              style={[styles.button, styles.secondaryButton]}
              onPress={handleManualInput}
            >
              <Text style={[styles.buttonText, styles.secondaryText]}>
                ⌨️ Manuel Giriş
              </Text>
            </TouchableOpacity>
          </View>
        </View>
      ) : (
        <View style={styles.resultContainer}>
          <Text style={styles.sectionTitle}>Okunan MRZ Bilgileri</Text>

          <View style={styles.card}>
            <InfoRow label="Ad" value={parsedData.firstName} />
            <InfoRow label="Soyad" value={parsedData.lastName} />
            <InfoRow label="Belge No" value={parsedData.documentNumber} />
            <InfoRow label="Seri No" value={parsedData.serialNumber} />
            <InfoRow
              label="Doğum Tarihi"
              value={formatDate(parsedData.dateOfBirth)}
            />
            <InfoRow
              label="Son Geçerlilik"
              value={formatDate(parsedData.expiryDate)}
            />
            <InfoRow label="Uyruk" value={parsedData.nationality} />
            <InfoRow label="Cinsiyet" value={parsedData.gender} />
          </View>

          <TouchableOpacity style={styles.button} onPress={navigateToNFC}>
            <Text style={styles.buttonText}>NFC ile Okut →</Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={[styles.button, styles.secondaryButton]}
            onPress={resetScan}
          >
            <Text style={[styles.buttonText, styles.secondaryText]}>
              Tekrar Tara
            </Text>
          </TouchableOpacity>
        </View>
      )}
    </View>
  );
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.row}>
      <Text style={styles.label}>{label}</Text>
      <Text style={styles.value}>{value || "-"}</Text>
    </View>
  );
}

function formatDate(yymmdd: string): string {
  if (yymmdd.length !== 6) return yymmdd;
  const yy = parseInt(yymmdd.substring(0, 2), 10);
  const mm = yymmdd.substring(2, 4);
  const dd = yymmdd.substring(4, 6);
  const year = yy > 50 ? 1900 + yy : 2000 + yy;
  return `${dd}.${mm}.${year}`;
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#f5f5f5",
  },
  centered: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
    padding: 24,
  },
  message: {
    fontSize: 16,
    color: "#666",
    textAlign: "center",
    marginBottom: 24,
  },
  scanContainer: {
    flex: 1,
  },
  infoBox: {
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: "#fff",
    margin: 16,
    padding: 16,
    borderRadius: 12,
    gap: 12,
  },
  infoIcon: {
    fontSize: 32,
  },
  infoText: {
    flex: 1,
    fontSize: 14,
    color: "#555",
    lineHeight: 20,
  },
  actions: {
    flex: 1,
    justifyContent: "center",
    padding: 24,
    gap: 16,
  },
  processingInline: {
    flexDirection: "row",
    alignItems: "center",
  },
  resultContainer: {
    flex: 1,
    padding: 16,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: "bold",
    color: "#333",
    marginBottom: 12,
  },
  card: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 16,
    marginBottom: 24,
    shadowColor: "#000",
    shadowOpacity: 0.05,
    shadowRadius: 8,
    shadowOffset: { width: 0, height: 2 },
    elevation: 2,
  },
  row: {
    flexDirection: "row",
    justifyContent: "space-between",
    paddingVertical: 10,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: "#eee",
  },
  label: {
    fontSize: 14,
    color: "#888",
    fontWeight: "500",
  },
  value: {
    fontSize: 14,
    color: "#333",
    fontWeight: "600",
  },
  button: {
    backgroundColor: "#007AFF",
    paddingVertical: 16,
    borderRadius: 16,
    alignItems: "center",
    marginBottom: 8,
  },
  buttonText: {
    color: "#fff",
    fontSize: 16,
    fontWeight: "600",
  },
  secondaryButton: {
    backgroundColor: "transparent",
    borderWidth: 1,
    borderColor: "#007AFF",
  },
  secondaryText: {
    color: "#007AFF",
  },
  disabledButton: {
    opacity: 0.7,
  },
});
