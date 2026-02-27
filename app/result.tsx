import { useMemo } from "react";
import {
    View,
    Text,
    StyleSheet,
    TouchableOpacity,
    ScrollView,
} from "react-native";
import { useRouter, useLocalSearchParams } from "expo-router";
import { SafeAreaView } from "react-native-safe-area-context";
import type { PassportData } from "../modules/passport-reader";

export default function ResultScreen() {
    const router = useRouter();
    const { data } = useLocalSearchParams<{ data: string }>();

    const passportData: PassportData | null = useMemo(() => {
        try {
            return data ? JSON.parse(data) : null;
        } catch {
            return null;
        }
    }, [data]);

    const prettyJSON = useMemo(() => {
        if (!passportData) return "{}";
        return JSON.stringify(passportData, null, 2);
    }, [passportData]);

    if (!passportData) {
        return (
            <SafeAreaView style={styles.container}>
                <View style={styles.centered}>
                    <Text style={styles.errorText}>Veri bulunamadı.</Text>
                </View>
            </SafeAreaView>
        );
    }

    return (
        <SafeAreaView style={styles.container} edges={["bottom"]}>
            <View style={styles.header}>
                <Text style={styles.headerTitle}>Kimlik Bilgileri (JSON)</Text>
            </View>

            <ScrollView style={styles.jsonContainer} contentContainerStyle={styles.jsonContent}>
                <Text style={styles.jsonText} selectable>
                    {prettyJSON}
                </Text>
            </ScrollView>

            <View style={styles.bottomActions}>
                <TouchableOpacity
                    style={styles.button}
                    onPress={() => router.replace("/")}
                    activeOpacity={0.8}
                >
                    <Text style={styles.buttonText}>🔄 Yeni Tarama</Text>
                </TouchableOpacity>
            </View>
        </SafeAreaView>
    );
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
    },
    errorText: {
        fontSize: 16,
        color: "#999",
    },
    header: {
        padding: 16,
        paddingBottom: 8,
    },
    headerTitle: {
        fontSize: 18,
        fontWeight: "bold",
        color: "#333",
    },
    jsonContainer: {
        flex: 1,
        marginHorizontal: 16,
        backgroundColor: "#1E1E1E",
        borderRadius: 12,
    },
    jsonContent: {
        padding: 16,
    },
    jsonText: {
        fontFamily: "Courier",
        fontSize: 14,
        color: "#D4D4D4",
        lineHeight: 22,
    },
    bottomActions: {
        padding: 16,
        paddingBottom: 8,
    },
    button: {
        backgroundColor: "#007AFF",
        paddingVertical: 16,
        borderRadius: 16,
        alignItems: "center",
    },
    buttonText: {
        color: "#fff",
        fontSize: 16,
        fontWeight: "600",
    },
});
