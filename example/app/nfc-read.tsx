import { useState, useEffect } from "react";
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  ActivityIndicator,
  Alert,
  Platform,
} from "react-native";
import { useRouter, useLocalSearchParams } from "expo-router";

// Conditionally import native module — falls back gracefully in Expo Go
let PassportReader: {
  readPassport: (s: string, d: string, e: string) => Promise<any>;
  isNFCSupported: () => boolean;
} | null = null;

try {
  PassportReader = require("passport-reader");
} catch {
  // Module not available (e.g. running in Expo Go)
  PassportReader = null;
}

export default function NFCReadScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<{
    serialNumber: string;
    dateOfBirth: string;
    expiryDate: string;
    firstName: string;
    lastName: string;
  }>();

  const [isScanning, setIsScanning] = useState(false);
  const [nfcSupported, setNfcSupported] = useState<boolean | null>(null);

  useEffect(() => {
    try {
      const supported = PassportReader?.isNFCSupported() ?? false;
      setNfcSupported(supported);
    } catch {
      setNfcSupported(false);
    }
  }, []);

  const startNFCScan = async () => {
    if (!params.serialNumber || !params.dateOfBirth || !params.expiryDate) {
      Alert.alert("Hata", "MRZ bilgileri eksik.");
      return;
    }

    if (!PassportReader) {
      Alert.alert(
        "Hata",
        "NFC modülü yüklenemedi. Lütfen uygulamayı development build olarak çalıştırın (Expo Go desteklemez).",
      );
      return;
    }

    setIsScanning(true);

    try {
      const passportData = await PassportReader.readPassport(
        params.serialNumber,
        params.dateOfBirth,
        params.expiryDate,
      );

      setIsScanning(false);

      router.replace({
        pathname: "/result",
        params: {
          data: JSON.stringify(passportData),
        },
      });
    } catch (error: any) {
      setIsScanning(false);
      const message = error?.message || "Bilinmeyen hata oluştu.";
      Alert.alert("NFC Okuma Hatası", message);
    }
  };

  const formatDate = (yymmdd: string): string => {
    if (!yymmdd || yymmdd.length !== 6) return yymmdd || "-";
    const yy = parseInt(yymmdd.substring(0, 2), 10);
    const mm = yymmdd.substring(2, 4);
    const dd = yymmdd.substring(4, 6);
    const year = yy > 50 ? 1900 + yy : 2000 + yy;
    return `${dd}.${mm}.${year}`;
  };

  return (
    <View style={styles.container}>
      <View style={styles.infoBox}>
        <Text style={styles.infoIcon}>📱</Text>
        <Text style={styles.infoText}>
          Lütfen aşağıdaki bilgileri doğruladıktan sonra kimliği telefonunuzun
          arkasına tutarak okutmayı başlatın.
        </Text>
      </View>

      <View style={styles.card}>
        <Text style={styles.sectionTitle}>Kimlik Bilgileri</Text>
        <InfoRow label="Ad" value={params.firstName || "-"} />
        <InfoRow label="Soyad" value={params.lastName || "-"} />
        <InfoRow label="Seri No" value={params.serialNumber || "-"} />
        <InfoRow
          label="Doğum Tarihi"
          value={formatDate(params.dateOfBirth || "")}
        />
        <InfoRow
          label="Son Geçerlilik"
          value={formatDate(params.expiryDate || "")}
        />
      </View>

      {nfcSupported === false && (
        <View style={styles.warningBox}>
          <Text style={styles.warningText}>
            ⚠️ Bu cihazda NFC kullanılamıyor veya devre dışı.
            {Platform.OS === "android"
              ? " Lütfen NFC ayarlarını kontrol edin."
              : ""}
          </Text>
        </View>
      )}

      <View style={styles.bottomActions}>
        <TouchableOpacity
          style={[
            styles.button,
            (isScanning || nfcSupported === false) && styles.disabledButton,
          ]}
          onPress={startNFCScan}
          disabled={isScanning || nfcSupported === false}
          activeOpacity={0.8}
        >
          {isScanning ? (
            <View style={styles.scanningRow}>
              <ActivityIndicator color="#fff" size="small" />
              <Text style={styles.buttonText}>Okutma Başlatılıyor...</Text>
            </View>
          ) : (
            <Text style={styles.buttonText}>📡 Okutmaya Başla</Text>
          )}
        </TouchableOpacity>
      </View>
    </View>
  );
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.row}>
      <Text style={styles.label}>{label}</Text>
      <Text style={styles.value}>{value}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#f5f5f5",
    padding: 16,
  },
  infoBox: {
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: "#fff",
    padding: 16,
    borderRadius: 12,
    marginBottom: 16,
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
  card: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 16,
    shadowColor: "#000",
    shadowOpacity: 0.05,
    shadowRadius: 8,
    shadowOffset: { width: 0, height: 2 },
    elevation: 2,
  },
  sectionTitle: {
    fontSize: 16,
    fontWeight: "bold",
    color: "#333",
    marginBottom: 8,
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
  },
  value: {
    fontSize: 14,
    color: "#333",
    fontWeight: "600",
  },
  warningBox: {
    backgroundColor: "#FFF3CD",
    padding: 12,
    borderRadius: 8,
    marginTop: 16,
  },
  warningText: {
    color: "#856404",
    fontSize: 13,
    lineHeight: 18,
  },
  bottomActions: {
    flex: 1,
    justifyContent: "flex-end",
    paddingBottom: 32,
  },
  button: {
    backgroundColor: "#007AFF",
    paddingVertical: 16,
    borderRadius: 16,
    alignItems: "center",
  },
  disabledButton: {
    backgroundColor: "#B0B0B0",
  },
  buttonText: {
    color: "#fff",
    fontSize: 16,
    fontWeight: "600",
  },
  scanningRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
  },
});
