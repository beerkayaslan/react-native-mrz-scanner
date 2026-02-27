import { View, Text, StyleSheet, TouchableOpacity } from "react-native";
import { useRouter } from "expo-router";
import { SafeAreaView } from "react-native-safe-area-context";

export default function HomeScreen() {
    const router = useRouter();

    return (
        <SafeAreaView style={styles.container}>
            <View style={styles.content}>
                <View style={styles.iconContainer}>
                    <Text style={styles.icon}>🪪</Text>
                </View>

                <Text style={styles.title}>Kimlik Doğrulama</Text>
                <Text style={styles.subtitle}>
                    TC Kimlik Kartı veya Pasaport doğrulamak için taramayı başlatın
                </Text>
            </View>

            <TouchableOpacity
                style={styles.button}
                onPress={() => router.push("/mrz-scan")}
                activeOpacity={0.8}
            >
                <Text style={styles.buttonText}>Kimlik Doğrula</Text>
            </TouchableOpacity>
        </SafeAreaView>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: "#fff",
        padding: 24,
        justifyContent: "space-between",
    },
    content: {
        flex: 1,
        justifyContent: "center",
        alignItems: "center",
    },
    iconContainer: {
        width: 120,
        height: 120,
        borderRadius: 60,
        backgroundColor: "#E8F5E9",
        justifyContent: "center",
        alignItems: "center",
        marginBottom: 32,
    },
    icon: {
        fontSize: 56,
    },
    title: {
        fontSize: 28,
        fontWeight: "bold",
        color: "#1a1a1a",
        marginBottom: 12,
        textAlign: "center",
    },
    subtitle: {
        fontSize: 16,
        color: "#666",
        textAlign: "center",
        lineHeight: 24,
        paddingHorizontal: 16,
    },
    button: {
        backgroundColor: "#007AFF",
        paddingVertical: 16,
        borderRadius: 16,
        alignItems: "center",
        marginBottom: 16,
    },
    buttonText: {
        color: "#fff",
        fontSize: 18,
        fontWeight: "600",
    },
});
