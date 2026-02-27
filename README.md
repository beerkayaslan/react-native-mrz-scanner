# rn-mrz-scanner

A React Native [Expo module](https://docs.expo.dev/modules/overview/) that opens a native full-screen camera scanner to read the **MRZ (Machine Readable Zone)** from passports and ID cards.

| Platform | OCR Engine |
| -------- | --------------------------------- |
| iOS | Apple Vision (`VNRecognizeTextRequest`) |
| Android | Google ML Kit Text Recognition |

Supports **TD-1** (ID cards — 3 × 30 chars) and **TD-3** (passports — 2 × 44 chars).

---

## Installation

```bash
npx expo install rn-mrz-scanner
```

or

```bash
npm install rn-mrz-scanner
# yarn add rn-mrz-scanner
```

### Expo Config Plugin (managed workflow)

Add the plugin to your `app.json` / `app.config.js`:

```json
{
  "expo": {
    "plugins": [
      [
        "rn-mrz-scanner",
        {
          "cameraPermissionText": "We need camera access to scan your document's MRZ."
        }
      ]
    ]
  }
}
```

Then rebuild:

```bash
npx expo prebuild --clean
npx expo run:ios   # or run:android
```

> The plugin automatically adds `NSCameraUsageDescription` (iOS) and `CAMERA` permission (Android).

---

## Usage

```tsx
import { scanMRZ } from "rn-mrz-scanner";

export default function App() {
  const handleScan = async () => {
    try {
      const mrz = await scanMRZ();
      console.log("MRZ result:", mrz);
      // TD-3 example:
      // "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\nL898902C36UTO7408122F1204159ZE184226B<<<<<10"
    } catch (error) {
      if (error.code === "ERR_CANCELLED") {
        console.log("User cancelled the scan");
      }
    }
  };

  return <Button title="Scan MRZ" onPress={handleScan} />;
}
```

### Return Value

`scanMRZ()` returns a `Promise<string>` containing the raw MRZ text. Lines are separated by `\n`.

- **TD-1 (ID card):** 3 lines, each 30 characters
- **TD-3 (Passport):** 2 lines, each 44 characters

You can parse the result with libraries like [`mrz`](https://www.npmjs.com/package/mrz).

---

## API

### `scanMRZ(): Promise<string>`

Opens a full-screen camera view that automatically detects and reads MRZ text.

**Throws:**

| Code | Description |
| --- | --- |
| `ERR_CANCELLED` | User dismissed the scanner |
| `ERR_NO_ACTIVITY` | (Android) No activity available |
| `ERR_UI` | (iOS) Could not present the scanner |
| `ERR_MRZ` | (Android) MRZ could not be read |

---

## Requirements

- **iOS:** 15.0+
- **Android:** API 21+ (CameraX)
- **Expo SDK:** 49+

---

## How It Works

1. A native full-screen camera view is presented.
2. Each frame is processed with OCR (Vision on iOS, ML Kit on Android).
3. Detected text is filtered and matched against MRZ regex patterns.
4. A `StringTracker` stabilises the result over multiple frames to avoid false positives.
5. Once a stable MRZ is detected, the camera closes and the result is returned.

---

## License

MIT
