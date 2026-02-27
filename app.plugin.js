const {
  withInfoPlist,
  withAndroidManifest,
  createRunOncePlugin,
} = require("expo/config-plugins");

const pkg = require("./package.json");

/**
 * Expo config plugin for rn-mrz-scanner.
 * Automatically adds camera permissions for iOS and Android.
 *
 * @param {import("expo/config").ExpoConfig} config
 * @param {{ cameraPermissionText?: string }} props
 */
function withMRZScanner(config, props = {}) {
  const cameraPermissionText =
    props.cameraPermissionText ||
    "This app needs camera access to scan MRZ codes on identity documents.";

  // iOS: Add NSCameraUsageDescription to Info.plist
  config = withInfoPlist(config, (config) => {
    if (!config.modResults.NSCameraUsageDescription) {
      config.modResults.NSCameraUsageDescription = cameraPermissionText;
    }
    return config;
  });

  // Android: Ensure CAMERA permission is in manifest
  config = withAndroidManifest(config, (config) => {
    const manifest = config.modResults.manifest;
    if (!manifest["uses-permission"]) {
      manifest["uses-permission"] = [];
    }
    const hasCamera = manifest["uses-permission"].some(
      (perm) => perm.$["android:name"] === "android.permission.CAMERA"
    );
    if (!hasCamera) {
      manifest["uses-permission"].push({
        $: { "android:name": "android.permission.CAMERA" },
      });
    }
    return config;
  });

  return config;
}

module.exports = createRunOncePlugin(withMRZScanner, pkg.name, pkg.version);
