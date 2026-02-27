import { Stack } from "expo-router";
import { StatusBar } from "expo-status-bar";

export default function RootLayout() {
    return (
        <>
            <StatusBar style="dark" />
            <Stack
                screenOptions={{
                    headerStyle: { backgroundColor: "#fff" },
                    headerTintColor: "#333",
                    headerTitleStyle: { fontWeight: "bold" },
                }}
            >
                <Stack.Screen
                    name="index"
                    options={{ title: "Kimlik Doğrulama", headerShown: false }}
                />
                <Stack.Screen name="mrz-scan" options={{ title: "Kimlik Tara" }} />
                <Stack.Screen name="nfc-read" options={{ title: "NFC Okuma" }} />
                <Stack.Screen
                    name="result"
                    options={{ title: "Sonuç", headerBackVisible: false }}
                />
            </Stack>
        </>
    );
}
